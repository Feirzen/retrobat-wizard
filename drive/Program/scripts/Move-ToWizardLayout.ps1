<#
    Move-ToWizardLayout.ps1 - the one-time move from _ClaudeWorkspace to
    _Wizard (wizard 3.2, 2026-10-26).

    Until 3.2 the wizard's folder was RetroBat\_ClaudeWorkspace, with about
    thirty folders and files side by side. 3.2 sorts everything into eight
    rooms in RetroBat\_Wizard (see Paths.ps1 for what each room is and the
    full old -> new map). This script does that move, ONCE, by itself.

    WHO RUNS IT
      - _ClaudeWorkspace\wizard\Launch-Wizard.vbs (the "bridge"), the first
        time anything starts the wizard after the 3.2 update. Every launcher a
        3.1 drive has (PLAY, the wizard button, desktop icons, the controller
        shortcut) points at that file, so whichever is used first does it.
      - the installer, after it has put 3.2 on a 3.1 setup.
      It always runs from a COPY in the computer's TEMP folder, so nothing in
      the folder being renamed is in use.

    WHAT IT DOES, IN ORDER (every step is safe to run again: a move that was
    cut short simply carries on next time)
      1. Waits for RetroBat to be closed and stops the wizard's own helpers
         (they run from the old folder and would keep it busy).
      2. Renames _ClaudeWorkspace to _Wizard.
      3. Sorts every file into its room (Paths.ps1's map). Where a 3.2 file
         already sits at the new place (the update put it there), the new
         program file wins and the old one goes to Cache\Trash; for a
         setting, the person's old file wins. Anything the map does not
         know goes to Owner\loose. NOTHING IS DELETED.
      4. Rewrites everything OUTSIDE that pointed in: RetroBat's start and
         end hooks, the Wii and Wii U launchers, PLAY.bat and the wizard
         button, browser-game .bat files in roms, the drive's own top-level
         buttons, and shortcuts (.lnk) at the top of the drive, on this
         computer's desktop and Start menu. Each changed file is backed up
         first (Backups\Archive\layout-move_<time>).
      5. Updates this computer's controller-shortcut helper if it has one.
      6. Sets the last update's "Go back" aside: going back across the move
         is not possible (the move is undone with -Undo instead).
      Every step is written to a journal, Program\update\layout-move.txt, and
      a log, Cache\logs\move.log. -Undo walks the journal backwards.

    ASCII ONLY, Windows PowerShell 5.1. Runs on Linux PowerShell 7 for the
    tests (no window, no shortcuts there).
#>
[CmdletBinding()]
param(
    [string]$Root = '',
    [switch]$Quiet,
    [switch]$Undo,
    [switch]$NoProcessCheck
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')

$script:OnWindows = ([Environment]::OSVersion.Platform -eq 'Win32NT')
$script:Stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$script:LogLines = New-Object System.Collections.ArrayList
$script:Journal = ''
$script:Form = $null; $script:Label = $null
$script:Counts = @{ Moved = 0; Trashed = 0; Loose = 0; Edited = 0; Links = 0 }

function Note([string]$m) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m
    [void]$script:LogLines.Add($line)
    if (-not $Quiet) { Write-Host $m }
}
function Show-Step([string]$m) {
    Note $m
    if ($null -ne $script:Label) { try { $script:Label.Text = $m; $script:Form.Refresh() } catch { } }
}
function Write-Journal([string]$Line) {
    if ($script:Journal -eq '') { return }
    $d = Split-Path -Parent $script:Journal
    if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
    [System.IO.File]::AppendAllText($script:Journal, ($Line + "`r`n"))
}
function Get-RootRel([string]$Full) {
    $b = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $f = [System.IO.Path]::GetFullPath($Full)
    if ($f.Length -le $b.Length) { return '' }
    return ($f.Substring($b.Length).TrimStart('\', '/') -replace '/', '\')
}
function New-Dir([string]$p) { if (-not (Test-Path -LiteralPath $p)) { [void](New-Item -ItemType Directory -Path $p -Force) } }

# Moves one file or folder (both full paths), journalled relative to RetroBat.
function Move-One([string]$From, [string]$To) {
    New-Dir (Split-Path -Parent $To)
    Move-Item -LiteralPath $From -Destination $To
    Write-Journal ("move`t" + (Get-RootRel $From) + "`t" + (Get-RootRel $To))
    $script:Counts.Moved++
}
# A free name under Cache\Trash\layout-move.
function Get-TrashPath([string]$Ws, [string]$Rel) {
    $base = Join-WizPath (Join-WizPath $Ws 'Cache\Trash\layout-move') $Rel
    $try = $base; $n = 2
    while (Test-Path -LiteralPath $try) { $try = "$base ($n)"; $n++ }
    return $try
}

# ---------------------------------------------------------------------------
#  3. Sorting into rooms
# ---------------------------------------------------------------------------
function Test-MapHasDeeper([string]$RelDir) {
    $pre = $RelDir.TrimEnd('\') + '\'
    foreach ($m in (Get-WizMoveMap)) {
        if ($m[0].Length -gt $pre.Length -and $m[0].StartsWith($pre, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Move-LegacyFile([string]$Ws, [string]$Rel) {
    $src = Join-WizPath $Ws $Rel
    $t = Get-WizNewPath $Rel
    if ($t -eq '') { $t = 'Owner\loose\' + $Rel; $script:Counts.Loose++ }
    $dst = Join-WizPath $Ws $t
    if ([System.IO.Path]::GetFullPath($src) -ieq [System.IO.Path]::GetFullPath($dst)) { return }
    if (Test-Path -LiteralPath $dst) {
        if ($t -match '^(Program|Buttons)\\' -or $t -match '^Cache\\') {
            # the update already put the 3.2 program file here: it wins
            Move-One $src (Get-TrashPath $Ws ('old\' + $Rel))
            $script:Counts.Trashed++
        }
        else {
            # a setting or a person's file: the one they already had wins
            Move-One $dst (Get-TrashPath $Ws ('replaced\' + $t))
            Move-One $src $dst
        }
        return
    }
    Move-One $src $dst
}

# Every file under $SrcFull into the same place under $DstFull; a file
# already there stays, the incoming one goes to the trash.
function Merge-Into([string]$Ws, [string]$SrcFull, [string]$DstFull) {
    foreach ($f in @(Get-ChildItem -LiteralPath $SrcFull -Recurse -File -Force)) {
        $sub = $f.FullName.Substring($SrcFull.Length).TrimStart('\', '/')
        $d = Join-WizPath $DstFull $sub
        if (-not (Test-Path -LiteralPath $d)) { Move-One $f.FullName $d }
        else { Move-One $f.FullName (Get-TrashPath $Ws ('old\' + (Get-RootRel $f.FullName))) }
    }
    try { Remove-Item -LiteralPath $SrcFull -Recurse -Force; Write-Journal ("rmdir`t" + (Get-RootRel $SrcFull)) } catch { }
}

function Move-LegacyDir([string]$Ws, [string]$Rel) {
    $src = Join-WizPath $Ws $Rel
    $t = Get-WizNewPath ($Rel + '\')
    # Only the capitals change (apps -> Apps): Windows sees one folder, so it
    # goes through a temporary name to take the new spelling.
    if ($t -ne '' -and $t.TrimEnd('\') -ieq $Rel) {
        if ($t.TrimEnd('\') -ceq $Rel) { return }
        $tmp = Join-WizPath $Ws ($Rel + '.moving')
        Move-One $src $tmp
        $dst = Join-WizPath $Ws $t.TrimEnd('\')
        if (-not (Test-Path -LiteralPath $dst)) { Move-One $tmp $dst } else { Merge-Into $Ws $tmp $dst }
        return
    }
    if ($t -ne '' -and $t.EndsWith('\') -and -not (Test-MapHasDeeper $Rel)) {
        $dst = Join-WizPath $Ws $t.TrimEnd('\')
        if (-not (Test-Path -LiteralPath $dst)) { Move-One $src $dst; return }
    }
    if ($t -eq '' -and -not (Test-MapHasDeeper $Rel)) {
        $dst = Join-WizPath $Ws ('Owner\loose\' + $Rel)
        if (-not (Test-Path -LiteralPath $dst)) { Move-One $src $dst; $script:Counts.Loose++; return }
    }
    foreach ($c in @(Get-ChildItem -LiteralPath $src -Force)) {
        $cr = $Rel + '\' + $c.Name
        if ($c.PSIsContainer) { Move-LegacyDir $Ws $cr } else { Move-LegacyFile $Ws $cr }
    }
    if (@(Get-ChildItem -LiteralPath $src -Force).Count -eq 0) {
        Remove-Item -LiteralPath $src -Force
        Write-Journal ("rmdir`t" + (Get-RootRel $src))
    }
}

function Move-AllLegacy([string]$Ws) {
    $keep = @($script:WizRooms + @('START HERE.txt', 'version.txt'))
    foreach ($item in @(Get-ChildItem -LiteralPath $Ws -Force)) {
        if ($keep -ccontains $item.Name) { continue }
        if ($item.PSIsContainer) { Move-LegacyDir $Ws $item.Name } else { Move-LegacyFile $Ws $item.Name }
    }
}

# ---------------------------------------------------------------------------
#  4. Everything outside that points in
# ---------------------------------------------------------------------------
#  _ClaudeWorkspace\<old path> becomes _Wizard\<new path>. The old path is
#  read up to the first character that cannot be part of one; then the
#  longest piece of it that the map knows is translated and the rest kept.
function Convert-LegacyText([string]$Text) {
    $rx = [regex]'_ClaudeWorkspace(?<rest>[\\/][^"''\r\n%,;|<>()]*)?'
    return $rx.Replace($Text, [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $rest = $m.Groups['rest'].Value
        if ($rest -eq '') { return '_Wizard' }
        $sep = $rest.Substring(0, 1)
        $body = $rest.Substring(1)
        # try the whole thing, then shorter and shorter (at spaces and slashes)
        $cuts = New-Object System.Collections.ArrayList
        [void]$cuts.Add($body.Length)
        for ($i = $body.Length - 1; $i -gt 0; $i--) { if (' \/'.Contains($body.Substring($i, 1))) { [void]$cuts.Add($i) } }
        foreach ($c in $cuts) {
            $piece = $body.Substring(0, $c).TrimEnd(' ', '.')   # a sentence's full stop is not part of the name
            if ($piece -eq '') { continue }
            $tail = $body.Substring($piece.Length)
            $p2 = $piece -replace '/', '\'
            $n = Get-WizNewPath $p2
            if ($n -eq '' -and -not $p2.EndsWith('\')) { $n = Get-WizNewPath ($p2 + '\'); if ($n -ne '') { $n = $n.TrimEnd('\') } }
            if ($n -ne '') {
                if ($sep -eq '/') { $n = $n -replace '\\', '/' }
                return ('_Wizard' + $sep + $n + $tail)
            }
        }
        return ('_Wizard' + $rest)
    })
}

function Get-OutsideFiles {
    $files = New-Object System.Collections.ArrayList
    $add = { param($dir, $patterns, [bool]$deep)
        if (-not (Test-Path -LiteralPath $dir)) { return }
        foreach ($pat in $patterns) {
            $opt = @{ LiteralPath = $dir; Filter = $pat; File = $true; Force = $true; ErrorAction = 'SilentlyContinue' }
            if ($deep) { $opt.Recurse = $true }
            foreach ($f in @(Get-ChildItem @opt)) { [void]$files.Add($f.FullName) }
        }
    }
    $code = @('*.bat', '*.cmd', '*.vbs', '*.ps1')
    & $add $Root $code $false
    & $add (Join-WizPath $Root 'emulationstation\.emulationstation\scripts') $code $true
    & $add (Join-WizPath $Root 'emulationstation\.emulationstation') @('es_systems*.cfg') $false
    & $add (Join-WizPath $Root 'system\scripts') $code $false
    # the master copies of those files (a drive's own RetroBat Wizard.bat
    # master came over from 3.1 still pointing at _ClaudeWorkspace, 2026-10-26)
    foreach ($m in @('Program\restore', 'Program\restore-off')) { & $add (Join-WizPath (Join-WizPath $Root $script:WizFolderName) $m) @('*.bat', '*.cmd', '*.vbs', '*.ps1', '*.xml') $true }
    $roms = Join-WizPath $Root 'roms'
    if (Test-Path -LiteralPath $roms) {
        foreach ($d in @(Get-ChildItem -LiteralPath $roms -Directory -Force -ErrorAction SilentlyContinue)) { & $add $d.FullName $code $false }
    }
    # the drive's own top-level buttons, when RetroBat sits at the top of a drive
    $parent = Split-Path -Parent ([System.IO.Path]::GetFullPath($Root))
    if ($parent -and ([System.IO.Path]::GetPathRoot($parent) -eq $parent -or $parent.TrimEnd('\', '/') -eq ([System.IO.Path]::GetPathRoot($parent)).TrimEnd('\', '/'))) {
        & $add $parent @('*.bat', '*.cmd', '*.vbs', '*.txt') $false
    }
    return @($files | Select-Object -Unique)
}

function Update-OutsideFiles([string]$Ws) {
    $backup = Join-WizPath $Ws ('Backups\Archive\layout-move_' + $script:Stamp)
    foreach ($f in (Get-OutsideFiles)) {
        $bytes = [System.IO.File]::ReadAllBytes($f)
        $text = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
        if ($text.IndexOf('_ClaudeWorkspace', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        $new = Convert-LegacyText $text
        if ($new -ceq $text) { continue }
        $rel = Get-RootRel $f
        if ($rel -eq '') { $rel = 'drive-root\' + [System.IO.Path]::GetFileName($f) }
        $bk = Join-WizPath $backup ('outside\' + $rel)
        New-Dir (Split-Path -Parent $bk)
        [System.IO.File]::WriteAllBytes($bk, $bytes)
        [System.IO.File]::WriteAllBytes($f, [System.Text.Encoding]::GetEncoding(28591).GetBytes($new))
        Write-Journal ("edit`t" + $f + "`t" + $bk)
        $script:Counts.Edited++
        Note ('rewrote ' + $f)
    }
}

function Update-Shortcuts([string]$Ws) {
    if (-not $script:OnWindows) { return }
    try { $sh = New-Object -ComObject WScript.Shell } catch { Note ('shortcuts: no WScript.Shell - ' + $_.Exception.Message); return }
    $dirs = @()
    $parent = Split-Path -Parent ([System.IO.Path]::GetFullPath($Root))
    if ($parent) { $dirs += $parent }
    $dirs += $Root
    foreach ($k in @('Desktop', 'CommonDesktopDirectory', 'Programs', 'CommonPrograms', 'StartMenu')) {
        try { $p = [Environment]::GetFolderPath($k); if ($p) { $dirs += $p } } catch { }
    }
    foreach ($d in ($dirs | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $deep = ($d -match 'Start Menu')
        $opt = @{ LiteralPath = $d; Filter = '*.lnk'; File = $true; Force = $true; ErrorAction = 'SilentlyContinue' }
        if ($deep) { $opt.Recurse = $true }
        foreach ($f in @(Get-ChildItem @opt)) {
            try {
                $l = $sh.CreateShortcut($f.FullName)
                $all = ($l.TargetPath + '|' + $l.Arguments + '|' + $l.WorkingDirectory + '|' + $l.IconLocation)
                if ($all -notmatch '_ClaudeWorkspace') { continue }
                $bk = Join-WizPath $Ws ('Backups\Archive\layout-move_' + $script:Stamp + '\shortcuts\' + $f.Name)
                New-Dir (Split-Path -Parent $bk); Copy-Item -LiteralPath $f.FullName -Destination $bk -Force
                $l.TargetPath = Convert-LegacyText $l.TargetPath
                $l.Arguments = Convert-LegacyText $l.Arguments
                $l.WorkingDirectory = Convert-LegacyText $l.WorkingDirectory
                $l.IconLocation = Convert-LegacyText $l.IconLocation
                $l.Save()
                Write-Journal ("edit`t" + $f.FullName + "`t" + $bk)
                $script:Counts.Links++
                Note ('shortcut updated: ' + $f.FullName)
            } catch { Note ('shortcut skipped: ' + $f.FullName + ' - ' + $_.Exception.Message) }
        }
    }
}

# ---------------------------------------------------------------------------
#  1. Nothing may be running
# ---------------------------------------------------------------------------
function Wait-ForQuiet([string]$OldWs) {
    if ($NoProcessCheck -or -not $script:OnWindows) { return $true }
    while ($true) {
        $rb = @(Get-Process -Name 'emulationstation', 'RetroBat', 'BatGui', 'emulatorLauncher' -ErrorAction SilentlyContinue)
        if ($rb.Count -eq 0) { break }
        if ($Quiet) { return $false }
        $a = 2
        try { $a = (New-Object -ComObject WScript.Shell).Popup("RetroBat is open. Close it, then press Retry.`n`n(The wizard is tidying its folder once, after the 3.2 update.)", 0, 'RetroBat Wizard', 53) } catch { }
        if ($a -ne 4) { return $false }   # 4 = Retry
    }
    # the wizard's own helpers run from the old folder
    $me = $PID
    $mark = '\' + (Split-Path -Leaf $OldWs) + '\'
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe' OR Name='wscript.exe'" -ErrorAction SilentlyContinue)) {
        if ($p.ProcessId -eq $me) { continue }
        if ([string]$p.CommandLine -like ('*' + $mark + '*') -and [string]$p.CommandLine -notlike '*Move-ToWizardLayout*') {
            Note ('stopping a helper: ' + ([string]$p.CommandLine).Substring(0, [Math]::Min(120, ([string]$p.CommandLine).Length)))
            try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop } catch { }
        }
    }
    Start-Sleep -Milliseconds 800
    return $true
}

# ---------------------------------------------------------------------------
#  -Undo
# ---------------------------------------------------------------------------
function Invoke-Undo {
    $ws = Join-WizPath $Root $script:WizFolderName
    $j = Join-WizPath $ws 'Program\update\layout-move.txt'
    if (-not (Test-Path -LiteralPath $j)) { Note 'undo: no journal, nothing to undo'; return $false }
    $lines = @([System.IO.File]::ReadAllLines($j) | Where-Object { $_ -ne '' })
    [System.IO.File]::Copy($j, (Join-WizPath $Root ('layout-move-undone_' + $script:Stamp + '.txt')), $true)
    [array]::Reverse($lines)
    $renamed = $false
    foreach ($l in $lines) {
        $f = $l.Split("`t")
        switch ($f[0]) {
            'move' {
                $from = Join-WizPath $Root $f[2]; $to = Join-WizPath $Root $f[1]
                if ((Test-Path -LiteralPath $from) -and -not (Test-Path -LiteralPath $to)) { New-Dir (Split-Path -Parent $to); Move-Item -LiteralPath $from -Destination $to }
            }
            'rmdir' { New-Dir (Join-WizPath $Root $f[1]) }
            'edit' { if (Test-Path -LiteralPath $f[2]) { Copy-Item -LiteralPath $f[2] -Destination $f[1] -Force } }
            'rename' { $renamed = $true }
        }
    }
    if ($renamed) {
        $old = Join-WizPath $Root $script:WizOldFolderName
        if (-not (Test-Path -LiteralPath $old)) { Rename-Item -LiteralPath $ws -NewName $script:WizOldFolderName }
    }
    Note 'undo: done'
    return $true
}

# ===========================================================================
if ($Root -eq '') { $Root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent }
$Root = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
if ($Undo) { [void](Invoke-Undo); exit 0 }

$oldWs = Join-WizPath $Root $script:WizOldFolderName
$newWs = Join-WizPath $Root $script:WizFolderName
$result = 'nothing'
try {
    # The little window is only a nicety: if it cannot be drawn, the move
    # carries on without it (3.2 test, 2026-10-26: a colour call failed on
    # Windows PowerShell and stopped the whole move).
    if (-not $Quiet -and $script:OnWindows) { try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $script:Form = New-Object System.Windows.Forms.Form
        $script:Form.Text = 'RetroBat Wizard'; $script:Form.Width = 520; $script:Form.Height = 150
        $script:Form.StartPosition = 'CenterScreen'; $script:Form.FormBorderStyle = 'FixedDialog'; $script:Form.ControlBox = $false
        $script:Form.TopMost = $true; $script:Form.BackColor = 'Black'
        $t = New-Object System.Windows.Forms.Label
        $t.Text = 'Tidying the wizard''s folder (once, after the 3.2 update)'; $t.ForeColor = 'White'
        $t.Font = New-Object System.Drawing.Font('Segoe UI', 11, 'Bold'); $t.AutoSize = $true; $t.Location = New-Object System.Drawing.Point(18, 18)
        $script:Label = New-Object System.Windows.Forms.Label
        $script:Label.ForeColor = 'Silver'; $script:Label.Width = 470; $script:Label.Height = 40
        $script:Label.Location = New-Object System.Drawing.Point(18, 52); $script:Label.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
        $script:Form.Controls.Add($t); $script:Form.Controls.Add($script:Label)
        $script:Form.Show(); [void]$script:Form.Refresh()
    } catch { Note ('no progress window: ' + $_.Exception.Message); try { if ($null -ne $script:Form) { $script:Form.Close() } } catch { }; $script:Form = $null; $script:Label = $null } }

    if (-not (Test-Path -LiteralPath $oldWs) -and -not (Test-Path -LiteralPath $newWs)) { throw 'neither _ClaudeWorkspace nor _Wizard is here' }

    Show-Step 'Making sure nothing is running'
    if (Test-Path -LiteralPath $oldWs) {
        if (-not (Wait-ForQuiet $oldWs)) { $result = 'cancelled'; throw 'RetroBat is still open' }
    }

    # --- 2. the folder's new name -----------------------------------------
    if ((Test-Path -LiteralPath $oldWs) -and -not (Test-Path -LiteralPath $newWs)) {
        Show-Step 'Renaming _ClaudeWorkspace to _Wizard'
        $ok = $false; $why = ''
        for ($i = 0; $i -lt 15 -and -not $ok; $i++) {
            try { Rename-Item -LiteralPath $oldWs -NewName $script:WizFolderName -ErrorAction Stop; $ok = $true }
            catch { $why = $_.Exception.Message; Start-Sleep -Seconds 1 }
        }
        if (-not $ok) { throw ('the folder is in use and could not be renamed (' + $why + '). Close every RetroBat and wizard window, or restart the computer, then try again') }
        $script:Journal = Join-WizPath $newWs 'Program\update\layout-move.txt'
        Write-Journal ("rename`t" + $script:WizOldFolderName + "`t" + $script:WizFolderName)
    }
    elseif ((Test-Path -LiteralPath $oldWs) -and (Test-Path -LiteralPath $newWs)) {
        # both: an earlier move was cut short after making _Wizard, or a 3.2
        # install sat beside an old folder. Fold the old one in.
        Show-Step 'Folding the old _ClaudeWorkspace into _Wizard'
        $script:Journal = Join-WizPath $newWs 'Program\update\layout-move.txt'
        foreach ($item in @(Get-ChildItem -LiteralPath $oldWs -Force)) {
            $dst = Join-WizPath $newWs $item.Name
            if (-not (Test-Path -LiteralPath $dst)) { Move-One $item.FullName $dst }
            elseif ($item.PSIsContainer) {
                foreach ($f in @(Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Force)) {
                    $rel = $f.FullName.Substring($oldWs.Length).TrimStart('\', '/')
                    $d2 = Join-WizPath $newWs $rel
                    if (-not (Test-Path -LiteralPath $d2)) { Move-One $f.FullName $d2 }
                    else { Move-One $f.FullName (Get-TrashPath $newWs ('old\' + $rel)) }
                }
            }
            else { Move-One $item.FullName (Get-TrashPath $newWs ('old\' + $item.Name)) }
        }
        try { Remove-Item -LiteralPath $oldWs -Recurse -Force -ErrorAction Stop } catch { Note ('could not remove the empty old folder: ' + $_.Exception.Message) }
    }
    else { $script:Journal = Join-WizPath $newWs 'Program\update\layout-move.txt' }

    # --- 3. every file into its room ----------------------------------------
    Show-Step 'Sorting everything into its room'
    Move-AllLegacy $newWs
    foreach ($r in $script:WizRooms) { New-Dir (Join-WizPath $newWs $r) }
    New-Dir (Join-WizPath $newWs 'Cache\logs')

    # --- 4. everything outside that points in --------------------------------
    Show-Step 'Pointing RetroBat''s buttons and hooks at the new folder'
    Update-OutsideFiles $newWs
    Update-Shortcuts $newWs

    # --- 5. this computer's controller shortcut ------------------------------
    if ($script:OnWindows) {
        try {
            . (Join-WizPath $newWs 'Program\scripts\PadShortcut.ps1')
            Update-PadShortcut -Root $Root -Logger { param($m) Note $m }
        } catch { Note ('pad shortcut: ' + $_.Exception.Message) }
    }

    # --- 6. no going back across the move -------------------------------------
    $prev = Join-WizPath $newWs 'Program\update\previous'
    if (Test-Path -LiteralPath $prev) { Move-One $prev (Get-TrashPath $newWs 'update-previous') }

    [System.IO.File]::WriteAllText((Join-WizPath $newWs 'Program\update\layout.txt'), ("moved from _ClaudeWorkspace on {0}`r`n" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    Note ('done: {0} moved, {1} old program files set aside, {2} unknown kept in Owner\loose, {3} files and {4} shortcuts pointed at _Wizard' -f $script:Counts.Moved, $script:Counts.Trashed, $script:Counts.Loose, $script:Counts.Edited, $script:Counts.Links)
    $result = 'moved'
}
catch {
    Note ('MOVE STOPPED: ' + $_.Exception.Message)
    if ($result -ne 'cancelled') { $result = 'failed' }
    if (-not $Quiet -and $script:OnWindows -and $result -eq 'failed') {
        try { [void]([type]'System.Windows.Forms.MessageBox')::Show(("The wizard could not finish tidying its folder:`n`n" + $_.Exception.Message + "`n`nNothing was lost. Start the wizard again to carry on. Details: _Wizard\Cache\logs\move.log (or _ClaudeWorkspace if the folder was not renamed yet)."), 'RetroBat Wizard', 'OK', 'Warning') } catch { }
    }
}
finally {
    $logDir = $(if (Test-Path -LiteralPath $newWs) { Join-WizPath $newWs 'Cache\logs' } elseif (Test-Path -LiteralPath $oldWs) { $oldWs } else { '' })
    if ($logDir -ne '') {
        try { New-Dir $logDir; [System.IO.File]::AppendAllText((Join-WizPath $logDir 'move.log'), (($script:LogLines -join "`r`n") + "`r`n")) } catch { }
    }
    if ($null -ne $script:Form) { try { $script:Form.Close() } catch { } }
}
if ($result -eq 'moved' -or $result -eq 'nothing') { exit 0 } else { exit 1 }
