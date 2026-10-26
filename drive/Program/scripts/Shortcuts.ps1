<#
    Shortcuts.ps1 - the two icons at the top level of the drive.

    FUNCTIONS ONLY. Dot-source it; it has no side effects until something
    calls Update-RootShortcuts.

    THE PROBLEM THIS SOLVES. A .bat file cannot carry a custom icon, and a
    .lnk file stores an absolute path, which on a drive that gets a
    different letter on every computer is the oldest trap in this project.

    THE ANSWER. Nothing is shipped. The shortcuts are BUILT at run time by
    whichever button was pressed, pointed at wherever the drive is right
    now. The first click on a brand new computer is the plain .bat; every
    click after that, the nice icon is sitting there. No drive letter is
    ever stored on the drive, only in a file that is rewritten each time.

    WHERE THEY GO. The top level of the external drive, one folder ABOVE
    RetroBat, so the drive opens onto two clean icons and nobody has to go
    into the RetroBat folder unless they want to look under the hood. If
    RetroBat is NOT sitting at a drive root - somebody copied it to their
    desktop, say - the shortcuts are written beside the .bat files instead,
    because scattering files into a stranger's Documents folder would be
    rude and surprising.

    WHAT THEY POINT AT. wizard\Launch-Wizard.vbs, through wscript.exe, and
    NOT at the .bat files. Going through the .bat leaves a black console
    window on screen for as long as the wizard is open, and closing that
    window kills the wizard with it. The .vbs starts the same command with
    window style 0, so clicking an icon shows nothing at all. If the .vbs is
    missing the shortcuts fall back to the .bat files, which still work.

    IT CAN NEVER BREAK ANYTHING. The whole body is wrapped, every failure
    is logged and swallowed, and a missing .ico just means a plain icon.
    Losing the shortcuts costs nothing: the two .bat files still work, and
    clicking either one builds them again.

    PURE ASCII on purpose. Windows PowerShell reads a script with no
    byte-order mark as ANSI.
#>

# The Play icon's name never changes. The wizard icon's name FOLLOWS the
# "name =" line in Settings\wizard.ini, so renaming the drive renames the icon.
# That is only safe because of the record file below: without it, a rename
# would leave the old .lnk stranded at the top of the drive with nothing able
# to tell it was ever ours.
$script:ShortcutPlayName   = 'Play RetroBat.lnk'
$script:ShortcutRecordFile = 'shortcuts.txt'


# Turns the drive's name into something Windows will accept as a file name.
function ConvertTo-ShortcutName {
    [CmdletBinding()]
    param([string] $WizardName = '')

    $n = [string]$WizardName
    foreach ($c in @('\', '/', ':', '*', '?', '"', '<', '>', '|')) { $n = $n.Replace($c, '') }
    $n = $n.Trim().Trim('.')
    if ([string]::IsNullOrWhiteSpace($n)) { $n = 'Setup Wizard' }
    return ($n + '.lnk')
}


# Works out where the shortcuts belong: the drive root above RetroBat when
# there is one, otherwise the RetroBat folder itself.
function Get-ShortcutFolder {
    [CmdletBinding()]
    param([string] $Root = '')

    if ([string]::IsNullOrWhiteSpace($Root)) { return '' }
    $parent = Split-Path $Root -Parent

    # '^[A-Za-z]:\\$' is exactly "R:\" and nothing else. Split-Path returns
    # '' when Root is already a drive root, and a real folder path when
    # RetroBat lives inside one.
    if ($parent -match '^[A-Za-z]:\\$') { return $parent }
    return $Root
}


# Finds the .bat at the drive root that opens the wizard window. It is
# found by what it DOES rather than by its name, because the record says a
# future owner may rename it to match a renamed wizard.
function Get-WizardBat {
    [CmdletBinding()]
    param([string] $Root = '')

    if ([string]::IsNullOrWhiteSpace($Root)) { return '' }
    $bats = @(Get-ChildItem -LiteralPath $Root -Filter '*.bat' -File -ErrorAction SilentlyContinue)
    foreach ($b in $bats) {
        if ($b.Name -eq 'PLAY.bat') { continue }
        $txt = ''
        try { $txt = [System.IO.File]::ReadAllText($b.FullName) } catch { continue }
        # SETUP RETROBAT.bat would otherwise match the rule below: it mentions
        # SetupWizard.ps1 and passes -Setup, not -Play. Harmless at a drive
        # root, but on a copy that is NOT at a drive root it sits in the same
        # folder as the wizard button and sorts first alphabetically, and then
        # the rename button would rename the SETUP button instead. It carries
        # a named marker rather than being recognised by a flag, because a
        # marker cannot turn up in a file by accident.
        if ($txt -like '*ROOT-SETUP-BUTTON*') { continue }
        # PLAY.bat is the one that passes -Play. The other one opens the
        # window. Both mention the .vbs and the .ps1, so the -Play flag is
        # what tells them apart.
        if ($txt -like '*SetupWizard.ps1*' -and $txt -notlike '*-Play*') { return $b.FullName }
    }
    return ''
}


# Writes one shortcut, and ONLY if something about it has actually changed.
# Rewriting an identical .lnk on every single launch would churn the drive
# and move its timestamp for no reason.
function Set-OneShortcut {
    [CmdletBinding()]
    param(
        $Shell,
        [string] $LinkPath    = '',
        [string] $Target      = '',
        [string] $Arguments   = '',
        [string] $WorkingDir  = '',
        [string] $IconFile    = '',
        [string] $Description = ''
    )

    $sc = $Shell.CreateShortcut($LinkPath)

    $icon = ''
    if (-not [string]::IsNullOrWhiteSpace($IconFile) -and (Test-Path -LiteralPath $IconFile)) {
        $icon = "$IconFile,0"
    }

    $same = ($sc.TargetPath -eq $Target) -and
            ($sc.Arguments -eq $Arguments) -and
            ($sc.WorkingDirectory -eq $WorkingDir) -and
            ($sc.Description -eq $Description) -and
            ($sc.IconLocation -eq $icon -or ($icon -eq '' -and $sc.IconLocation -eq ',0'))

    if ($same -and (Test-Path -LiteralPath $LinkPath)) { return 'unchanged' }

    $sc.TargetPath       = $Target
    $sc.Arguments        = $Arguments
    $sc.WorkingDirectory = $WorkingDir
    $sc.Description      = $Description
    # 7 is minimised. Nothing should appear either way now that the target is
    # the .vbs, but if the fallback to a .bat is ever taken this keeps its
    # console flash out of the middle of the screen.
    $sc.WindowStyle      = 7
    if ($icon -ne '') { $sc.IconLocation = $icon }
    $sc.Save()
    return 'written'
}


# The names written last time, so a rename can clear up after itself.
function Get-ShortcutRecord {
    [CmdletBinding()]
    param([string] $RecordPath = '')

    $out = @()
    if ([string]::IsNullOrWhiteSpace($RecordPath)) { return $out }
    if (-not (Test-Path -LiteralPath $RecordPath)) { return $out }
    try {
        foreach ($line in @([System.IO.File]::ReadAllLines($RecordPath))) {
            $t = $line.Trim()
            if ($t -eq '' -or $t.StartsWith('#')) { continue }
            $out += $t
        }
    } catch { }
    return $out
}


# Anything we wrote before and are not writing now is moved into
# _SAFE TO DELETE, never deleted. Nothing on this drive deletes anything, it
# moves things instead, and that rule applies to our own leftovers too.
function Move-RetiredShortcut {
    [CmdletBinding()]
    param(
        [string] $LinkPath = '',
        [string] $BinDir   = ''
    )

    if (-not (Test-Path -LiteralPath $LinkPath)) { return 'gone already' }
    if ([string]::IsNullOrWhiteSpace($BinDir))   { return 'nowhere to put it' }
    # Only ever a .lnk, and only ever one we recorded writing.
    if ([System.IO.Path]::GetExtension($LinkPath).ToLower() -ne '.lnk') { return 'not a shortcut' }
    try {
        if (-not (Test-Path -LiteralPath $BinDir)) {
            New-Item -ItemType Directory -Path $BinDir -Force -ErrorAction Stop | Out-Null
        }
        $name = Split-Path $LinkPath -Leaf
        $dest = Join-Path $BinDir $name
        if (Test-Path -LiteralPath $dest) {
            $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
            $dest = Join-Path $BinDir ("{0}_{1}.lnk" -f [System.IO.Path]::GetFileNameWithoutExtension($name), $stamp)
        }
        Move-Item -LiteralPath $LinkPath -Destination $dest -Force -ErrorAction Stop
        return 'retired'
    }
    catch { return ("could not retire: " + $_.Exception.Message) }
}


# The one entry point. Call it from anywhere; it never throws.
#
#   $r = Update-RootShortcuts -Root $Root -WizardName $name -Logger { param($m) Log $m }
#
# Returns a hashtable: Folder, Results (name -> unchanged/written/retired/...)
# and Problem (empty when nothing went wrong).
function Update-RootShortcuts {
    [CmdletBinding()]
    param(
        [string]      $Root       = '',
        [string]      $WizardName = 'Setup Wizard',
        [scriptblock] $Logger     = $null
    )

    $out = @{ Folder = ''; Results = @{}; Problem = '' }

    function Note([string]$m) {
        if ($null -ne $Logger) { try { & $Logger $m } catch { } }
    }

    try {
        if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root)) {
            $out.Problem = 'no RetroBat folder given'
            Note 'shortcuts: no RetroBat folder given, nothing done'
            return $out
        }

        $dest = Get-ShortcutFolder -Root $Root
        $out.Folder = $dest
        if ([string]::IsNullOrWhiteSpace($dest) -or -not (Test-Path -LiteralPath $dest)) {
            $out.Problem = 'nowhere to put them'
            Note 'shortcuts: nowhere to put them, nothing done'
            return $out
        }

        $wizardDir = Join-Path $Root '_Wizard\Program\wizard'
        $binDir    = Join-Path $Root '_Wizard\Cache\Trash'
        $record    = Join-Path $Root ('_Wizard\Settings\' + $script:ShortcutRecordFile)
        $vbs       = Join-Path $wizardDir 'Launch-Wizard.vbs'
        $wscript   = Join-Path $env:SystemRoot 'System32\wscript.exe'
        $playBat   = Join-Path $Root 'PLAY.bat'
        $wizBat    = Get-WizardBat -Root $Root
        $wizName   = ConvertTo-ShortcutName -WizardName $WizardName

        # The .vbs is what keeps a console window off the screen. Everything
        # still works without it, so this falls back rather than refusing.
        $useVbs = ((Test-Path -LiteralPath $vbs) -and (Test-Path -LiteralPath $wscript))
        if (-not $useVbs) { Note 'shortcuts: no Launch-Wizard.vbs, pointing at the .bat files instead' }

        $shell = $null
        try { $shell = New-Object -ComObject WScript.Shell }
        catch {
            $out.Problem = "WScript.Shell unavailable: $($_.Exception.Message)"
            Note ("shortcuts: could not start WScript.Shell - {0}" -f $_.Exception.Message)
            return $out
        }

        $written = @()
        try {
            # --- Play ---------------------------------------------------
            if ($useVbs -or (Test-Path -LiteralPath $playBat)) {
                if ($useVbs) { $t = $wscript; $a = ('//nologo "{0}" -Play' -f $vbs) }
                else         { $t = $playBat; $a = '' }
                $r = Set-OneShortcut -Shell $shell `
                        -LinkPath (Join-Path $dest $script:ShortcutPlayName) `
                        -Target $t -Arguments $a -WorkingDir $Root `
                        -IconFile (Join-Path $wizardDir 'play.ico') `
                        -Description 'Check the drive, then play'
                $out.Results[$script:ShortcutPlayName] = $r
                $written += $script:ShortcutPlayName
            }
            else {
                $out.Results[$script:ShortcutPlayName] = 'skipped, no PLAY.bat'
            }

            # --- the wizard ---------------------------------------------
            if ($useVbs -or -not [string]::IsNullOrWhiteSpace($wizBat)) {
                if ($useVbs) { $t = $wscript; $a = ('//nologo "{0}"' -f $vbs) }
                else         { $t = $wizBat;  $a = '' }
                $r = Set-OneShortcut -Shell $shell `
                        -LinkPath (Join-Path $dest $wizName) `
                        -Target $t -Arguments $a -WorkingDir $Root `
                        -IconFile (Join-Path $wizardDir 'wizard.ico') `
                        -Description $WizardName
                $out.Results[$wizName] = $r
                $written += $wizName
            }
            else {
                $out.Results[$wizName] = 'skipped, no wizard .bat'
            }
        }
        finally {
            # WPF holding an image file open is what stops a drive ejecting;
            # a live COM object is the same class of problem, so let it go.
            try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) } catch { }
        }

        # --- clear up after a rename ------------------------------------
        foreach ($old in @(Get-ShortcutRecord -RecordPath $record)) {
            if ($written -contains $old) { continue }
            $r = Move-RetiredShortcut -LinkPath (Join-Path $dest $old) -BinDir $binDir
            $out.Results[$old] = $r
        }

        # --- remember what we wrote -------------------------------------
        # Its own file, not Settings\state.ini: that one is rewritten whole
        # whenever RetroBat's version changes, so anything else kept in it
        # would silently vanish after an update.
        try {
            $lines = @(
                '# Written by scripts\Shortcuts.ps1. The icons it made last time.',
                '# If a name here is not made again, that .lnk is moved into',
                '# _Wizard\Cache\Trash so a rename leaves nothing behind.',
                '# Safe to delete; the worst that happens is one stale icon.'
            ) + $written
            $existing = @()
            if (Test-Path -LiteralPath $record) { $existing = @([System.IO.File]::ReadAllLines($record)) }
            if (($existing -join "`n") -ne ($lines -join "`n")) {
                [System.IO.File]::WriteAllLines($record, $lines, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
        catch { Note ("shortcuts: could not save the record - {0}" -f $_.Exception.Message) }

        foreach ($k in @($out.Results.Keys)) {
            Note ("shortcuts: {0} -> {1}  [{2}]" -f $k, $out.Results[$k], $dest)
        }
    }
    catch {
        $out.Problem = $_.Exception.Message
        Note ("shortcuts: failed, carrying on - {0}" -f $_.Exception.Message)
    }

    return $out
}


# ===========================================================================
#  THE FILES THAT BELONG AT THE TOP OF THE DRIVE
# ===========================================================================
#  Everything else this drive protects lives INSIDE the RetroBat folder, and
#  update-restore\ puts it back after an update. The drive root is one level
#  above that, so nothing was watching it - and SETUP RETROBAT.bat, the one
#  button somebody presses on a computer that has never seen this drive,
#  lives exactly there.
#
#  So _Wizard\Program\drive-root\ holds the masters and this puts any of
#  them back when it has gone missing. The button cannot be lost, and a drive
#  copied onto a new drive grows its own.
#
#  IT ONLY EVER ADDS. A file already at the top of the drive is left alone,
#  even when it differs from the master: somebody may have edited it on
#  purpose, and this drive does not overwrite or delete, ever. A file up
#  there that is not in drive-root\ is not touched at all. README.txt is
#  skipped by name.
#
#  NON-DRIVE-ROOT INSTALLS. Somebody who copies RetroBat onto their desktop
#  has no drive root to write to, so Get-ShortcutFolder hands back the
#  RetroBat folder and the button lands beside PLAY.bat. That is the same
#  answer the two icons already give, and it is why Get-WizardBat above had
#  to learn to skip the marker.
#
#  It never throws. Losing this costs one file that can be dragged back by
#  hand from drive-root\.
# ---------------------------------------------------------------------------
function Update-RootFiles {
    [CmdletBinding()]
    param(
        [string]      $Root   = '',
        [scriptblock] $Logger = $null
    )

    $out = @{ Folder = ''; Results = @{}; Problem = '' }

    function NoteF([string]$m) {
        if ($null -ne $Logger) { try { & $Logger $m } catch { } }
    }

    try {
        if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root)) {
            $out.Problem = 'no RetroBat folder given'
            return $out
        }

        $srcDir = Join-Path $Root '_Wizard\Program\drive-root'
        if (-not (Test-Path -LiteralPath $srcDir)) {
            # Not an error. A drive without the folder simply has nothing to
            # put back, and everything else still works.
            $out.Problem = 'no drive-root folder'
            return $out
        }

        $dest = Get-ShortcutFolder -Root $Root
        $out.Folder = $dest
        if ([string]::IsNullOrWhiteSpace($dest) -or -not (Test-Path -LiteralPath $dest)) {
            $out.Problem = 'nowhere to put them'
            NoteF 'root files: nowhere to put them, nothing done'
            return $out
        }

        foreach ($f in @(Get-ChildItem -LiteralPath $srcDir -File -ErrorAction SilentlyContinue)) {
            if ($f.Name -eq 'README.txt') { continue }
            $live = Join-Path $dest $f.Name
            if (Test-Path -LiteralPath $live) {
                $out.Results[$f.Name] = 'already there'
                continue
            }
            try {
                Copy-Item -LiteralPath $f.FullName -Destination $live -Force -ErrorAction Stop
                $out.Results[$f.Name] = 'put back'
                NoteF ("root files: put {0} back at {1}" -f $f.Name, $dest)
            }
            catch {
                $out.Results[$f.Name] = ("could not copy: " + $_.Exception.Message)
                NoteF ("root files: could not copy {0} - {1}" -f $f.Name, $_.Exception.Message)
            }
        }
    }
    catch {
        $out.Problem = $_.Exception.Message
        NoteF ("root files: failed, carrying on - {0}" -f $_.Exception.Message)
    }

    return $out
}
