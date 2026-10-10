<#
    LocalSetup.ps1 - the shortcuts that live on THIS computer.

    FUNCTIONS ONLY. Dot-source it; nothing happens until something calls
    Install-LocalSetup, Update-LocalSetup or Remove-LocalSetup.

    THE PROBLEM THIS SOLVES. scripts\Shortcuts.ps1 builds two icons at the
    top of the drive, which is perfect while the drive is plugged in. The
    moment it is unplugged, a copy of one of those shortcuts sitting on the
    Start Menu or the desktop goes blank: a .lnk stores its icon as a path,
    that path is on the drive, and the drive is gone. Windows draws nothing
    and keeps drawing nothing until the drive comes back.

    THE ANSWER. Put a copy of the icon files on the computer, and point the
    shortcuts at THAT copy. The target still lives on the drive, so clicking
    one without the drive plugged in politely fails, which is correct - but
    the icon is always there, so the Start Menu and the taskbar look right
    whether the drive is connected or not.

    NOTHING ON THE DRIVE STORES A DRIVE LETTER. The shortcuts written here
    do contain the current path, but they are written to the COMPUTER, not
    to the drive, and they are rewritten with the current path every time
    the wizard runs on that computer. That is the same trick Shortcuts.ps1
    uses, just pointed the other way.

    WHAT IT WRITES, and only what the caller asks for:

      %LOCALAPPDATA%\RetroBatDrive\          play.ico, wizard.ico,
                                             controllers.ico, installed.txt
      Start Menu\Programs\<drive name>\      Play, the wizard, Controllers
      Desktop\                               the same three

    THE CONTROLLERS SHORTCUT is the odd one out and is deliberately
    included: it opens Windows' own game controller panel (control joy.cpl),
    which lists every pad the computer can see and lets you test the
    buttons. It has nothing to do with the drive, so it keeps working when
    the drive is unplugged. It is the fastest way to answer "is this pad
    even connected?", which on a machine that gets four controllers plugged
    into it at a party is a question that comes up a lot.

    THE TASKBAR CANNOT BE DONE FROM A SCRIPT. Windows 10 and 11 removed the
    "pin to taskbar" verb that used to make this possible, and every method
    that still works is a registry forgery that breaks on the next Windows
    update. So this writes the Start Menu entry and the caller tells the
    user to right-click it and choose "Pin to taskbar", which takes two
    seconds and cannot break. Do not replace this with a clever version.

    IT CAN NEVER BREAK ANYTHING. Every entry point is wrapped, every failure
    is logged and swallowed, and the worst outcome is no shortcuts, which is
    exactly where the computer started.

    PURE ASCII on purpose. Windows PowerShell reads a script with no
    byte-order mark as ANSI.
#>

# The three shortcuts, and the icon each one wears. Names are fixed for the
# two that are not the wizard; the wizard's follows the "name =" line in
# wizard\wizard.ini, exactly as the drive-root icon does.
$script:LocalPlayName        = 'Play RetroBat.lnk'
$script:LocalControllersName = 'Controllers.lnk'
$script:LocalMarkerFile      = 'installed.txt'
$script:LocalIconNames       = @('play.ico', 'wizard.ico', 'controllers.ico')


# Where the local copies live. Under LOCALAPPDATA rather than APPDATA
# because these are machine-specific and there is no point roaming them to
# another computer that may not have ever seen this drive.
function Get-LocalSetupFolder {
    [CmdletBinding()]
    param()
    $base = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($base)) { return '' }
    return (Join-Path $base 'RetroBatDrive')
}


function Get-StartMenuFolder {
    [CmdletBinding()]
    param([string] $DriveName = 'RetroBat')
    $base = $env:APPDATA
    if ([string]::IsNullOrWhiteSpace($base)) { return '' }
    $safe = ConvertTo-LocalSafeName -Name $DriveName
    return (Join-Path $base ("Microsoft\Windows\Start Menu\Programs\" + $safe))
}


function Get-DesktopFolder {
    [CmdletBinding()]
    param()
    try   { return [Environment]::GetFolderPath('Desktop') }
    catch { return '' }
}


# Turns the drive's name into something Windows will accept as a file or
# folder name. Same rules as ConvertTo-ShortcutName in Shortcuts.ps1, but
# without the .lnk on the end, because this one also names a folder.
function ConvertTo-LocalSafeName {
    [CmdletBinding()]
    param([string] $Name = '')

    $n = [string]$Name
    foreach ($c in @('\', '/', ':', '*', '?', '"', '<', '>', '|')) { $n = $n.Replace($c, '') }
    $n = $n.Trim().Trim('.')
    if ([string]::IsNullOrWhiteSpace($n)) { $n = 'RetroBat' }
    return $n
}


# Has this computer been set up? The marker file is the only record, and it
# lives on the COMPUTER, so plugging the drive into a different machine
# correctly reports "not set up" there.
function Test-LocalSetupInstalled {
    [CmdletBinding()]
    param()
    $f = Get-LocalSetupFolder
    if ([string]::IsNullOrWhiteSpace($f)) { return $false }
    return (Test-Path -LiteralPath (Join-Path $f $script:LocalMarkerFile))
}


# Every shortcut path this computer was given last time, read back from the
# marker file. One path per line; lines starting with # are notes.
function Get-LocalSetupRecord {
    [CmdletBinding()]
    param()

    $out = @()
    $f = Get-LocalSetupFolder
    if ([string]::IsNullOrWhiteSpace($f)) { return $out }
    $marker = Join-Path $f $script:LocalMarkerFile
    if (-not (Test-Path -LiteralPath $marker)) { return $out }
    try {
        foreach ($line in @([System.IO.File]::ReadAllLines($marker))) {
            $t = $line.Trim()
            if ($t -eq '' -or $t.StartsWith('#')) { continue }
            $out += $t
        }
    } catch { }
    return $out
}


# Copies the drive's icons onto the computer. Returns the local folder, or
# an empty string if it could not be done.
function Copy-LocalIcons {
    [CmdletBinding()]
    param([string] $WizardDir = '')

    $dest = Get-LocalSetupFolder
    if ([string]::IsNullOrWhiteSpace($dest)) { return '' }
    if ([string]::IsNullOrWhiteSpace($WizardDir) -or -not (Test-Path -LiteralPath $WizardDir)) { return '' }

    try {
        if (-not (Test-Path -LiteralPath $dest)) {
            New-Item -ItemType Directory -Path $dest -Force -ErrorAction Stop | Out-Null
        }
    } catch { return '' }

    # Set when a picture on this computer was actually replaced. Install-
    # LocalSetup reads it and forces every shortcut to be written out again,
    # even the ones that are otherwise unchanged: Windows caches a shortcut's
    # icon and will happily keep showing the OLD one for a file it has already
    # read once. Re-saving the .lnk is what makes the shell look again.
    #
    # This is the bug Steven hit on 2026-09-18. The new GameCube icon reached
    # his computer correctly; the desktop kept drawing the old one, because
    # nothing about the shortcut itself had changed.
    $script:LocalIconsChanged = $false

    foreach ($n in $script:LocalIconNames) {
        $src = Join-Path $WizardDir $n
        if (-not (Test-Path -LiteralPath $src)) { continue }
        $dst = Join-Path $dest $n
        try {
            # Only copy when it would actually change something, so a
            # shortcut's icon cache is not invalidated on every launch.
            # Compared by CONTENT, not by date: the drive's own dates move
            # every time it is copied, and a date is not what was asked.
            $copy = $true
            if (Test-Path -LiteralPath $dst) {
                $a = Get-Item -LiteralPath $src
                $b = Get-Item -LiteralPath $dst
                if ($a.Length -eq $b.Length) {
                    try {
                        $ha = (Get-FileHash -LiteralPath $src -Algorithm MD5).Hash
                        $hb = (Get-FileHash -LiteralPath $dst -Algorithm MD5).Hash
                        if ($ha -eq $hb) { $copy = $false }
                    }
                    catch {
                        # No Get-FileHash on this machine: fall back to the
                        # old date test rather than copying on every launch.
                        if ($a.LastWriteTimeUtc -le $b.LastWriteTimeUtc) { $copy = $false }
                    }
                }
            }
            if ($copy) {
                Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop
                $script:LocalIconsChanged = $true
            }
        } catch { }
    }
    return $dest
}


# One shortcut, written only if something about it has changed. Same shape
# as Set-OneShortcut in Shortcuts.ps1 and for the same reason: rewriting an
# identical .lnk on every launch churns the disk and moves its timestamp for
# no reason.
function Set-OneLocalShortcut {
    [CmdletBinding()]
    param(
        $Shell,
        [string] $LinkPath    = '',
        [string] $Target      = '',
        [string] $Arguments   = '',
        [string] $WorkingDir  = '',
        [string] $IconFile    = '',
        [string] $Description = '',
        # Write the shortcut out even when nothing about it has changed.
        # Used when its icon FILE was just replaced - see Copy-LocalIcons.
        [switch] $Force
    )

    try {
        $dir = Split-Path $LinkPath -Parent
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        }
    } catch { return ("could not make the folder: " + $_.Exception.Message) }

    try {
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

        if ($same -and -not $Force -and (Test-Path -LiteralPath $LinkPath)) { return 'unchanged' }
        if ($same -and $Force) { $sc.IconLocation = ',0' ; $sc.Save() ; $sc = $Shell.CreateShortcut($LinkPath) }

        $sc.TargetPath       = $Target
        $sc.Arguments        = $Arguments
        $sc.WorkingDirectory = $WorkingDir
        $sc.Description      = $Description
        # 7 is minimised, so nothing flashes in the middle of the screen if a
        # fallback to a .bat is ever taken.
        $sc.WindowStyle      = 7
        if ($icon -ne '') { $sc.IconLocation = $icon }
        $sc.Save()
        return 'written'
    }
    catch { return ("failed: " + $_.Exception.Message) }
}


# Builds the list of shortcuts to write, without writing anything. Split out
# so the same list drives Install, Update and the tests.
function Get-LocalShortcutPlan {
    [CmdletBinding()]
    param(
        [string]   $Root       = '',
        [string]   $WizardName = 'RetroBat',
        [string[]] $Places     = @('start')
    )

    $plan = @()
    if ([string]::IsNullOrWhiteSpace($Root)) { return $plan }

    $wizardDir = Join-Path $Root '_ClaudeWorkspace\wizard'
    $vbs       = Join-Path $wizardDir 'Launch-Wizard.vbs'
    $wscript   = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $control   = Join-Path $env:SystemRoot 'System32\control.exe'
    $icons     = Get-LocalSetupFolder

    # The .vbs is what keeps a console window off the screen. Falling back to
    # the .bat files still works, it is just uglier, so this never refuses.
    $useVbs  = ((Test-Path -LiteralPath $vbs) -and (Test-Path -LiteralPath $wscript))
    $playBat = Join-Path $Root 'PLAY.bat'
    $wizBat  = ''
    if (Get-Command Get-WizardBat -ErrorAction SilentlyContinue) { $wizBat = Get-WizardBat -Root $Root }

    $wizLink = (ConvertTo-LocalSafeName -Name $WizardName) + '.lnk'

    $folders = @()
    foreach ($p in @($Places)) {
        switch ([string]$p) {
            'start'   { $f = Get-StartMenuFolder -DriveName $WizardName; if ($f -ne '') { $folders += $f } }
            'desktop' { $f = Get-DesktopFolder;                          if ($f -ne '') { $folders += $f } }
        }
    }

    foreach ($f in $folders) {
        if ($useVbs) {
            $plan += @{ Link = (Join-Path $f $script:LocalPlayName); Target = $wscript
                        Args = ('//nologo "{0}" -Play' -f $vbs); Work = $Root
                        Icon = (Join-Path $icons 'play.ico'); Desc = 'Check the drive, then play' }
            $plan += @{ Link = (Join-Path $f $wizLink); Target = $wscript
                        Args = ('//nologo "{0}"' -f $vbs); Work = $Root
                        Icon = (Join-Path $icons 'wizard.ico'); Desc = $WizardName }
        }
        else {
            if (Test-Path -LiteralPath $playBat) {
                $plan += @{ Link = (Join-Path $f $script:LocalPlayName); Target = $playBat
                            Args = ''; Work = $Root
                            Icon = (Join-Path $icons 'play.ico'); Desc = 'Check the drive, then play' }
            }
            if (-not [string]::IsNullOrWhiteSpace($wizBat)) {
                $plan += @{ Link = (Join-Path $f $wizLink); Target = $wizBat
                            Args = ''; Work = $Root
                            Icon = (Join-Path $icons 'wizard.ico'); Desc = $WizardName }
            }
        }

        # Windows' own controller panel. Nothing to do with the drive, so it
        # keeps working when the drive is unplugged, which is the point.
        $plan += @{ Link = (Join-Path $f $script:LocalControllersName); Target = $control
                    Args = 'joy.cpl'; Work = ''
                    Icon = (Join-Path $icons 'controllers.ico')
                    Desc = 'See and test the controllers plugged into this computer' }
    }

    return $plan
}


# Set this computer up. Returns a hashtable: Folder, Results (link -> what
# happened), StartMenu, Problem.
function Install-LocalSetup {
    [CmdletBinding()]
    param(
        [string]      $Root       = '',
        [string]      $WizardName = 'RetroBat',
        [string[]]    $Places     = @('start'),
        [scriptblock] $Logger     = $null
    )

    $out = @{ Folder = ''; Results = @{}; StartMenu = ''; Problem = '' }

    function Note([string]$m) {
        if ($null -ne $Logger) { try { & $Logger $m } catch { } }
    }

    try {
        if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root)) {
            $out.Problem = 'no RetroBat folder given'
            Note 'local setup: no RetroBat folder given, nothing done'
            return $out
        }

        $wizardDir = Join-Path $Root '_ClaudeWorkspace\wizard'
        $icons = Copy-LocalIcons -WizardDir $wizardDir
        $out.Folder = $icons
        if ([string]::IsNullOrWhiteSpace($icons)) {
            $out.Problem = 'could not copy the icons onto this computer'
            Note 'local setup: could not copy the icons, nothing done'
            return $out
        }

        $out.StartMenu = Get-StartMenuFolder -DriveName $WizardName

        $shell = $null
        try { $shell = New-Object -ComObject WScript.Shell }
        catch {
            $out.Problem = "WScript.Shell unavailable: $($_.Exception.Message)"
            Note ("local setup: could not start WScript.Shell - {0}" -f $_.Exception.Message)
            return $out
        }

        $written = @()
        try {
            # If a picture was just replaced, write every shortcut out again
            # whether or not it needs it, so Windows stops drawing the old one.
            $forceIcons = [bool]$script:LocalIconsChanged
            if ($forceIcons) { Note 'local setup: an icon changed, rewriting the shortcuts so Windows picks it up' }

            foreach ($p in @(Get-LocalShortcutPlan -Root $Root -WizardName $WizardName -Places $Places)) {
                $r = Set-OneLocalShortcut -Shell $shell -LinkPath $p.Link -Target $p.Target `
                        -Arguments $p.Args -WorkingDir $p.Work -IconFile $p.Icon -Description $p.Desc `
                        -Force:$forceIcons
                $out.Results[$p.Link] = $r
                if ($r -eq 'written' -or $r -eq 'unchanged') { $written += $p.Link }
            }
        }
        finally {
            # A live COM object holds things open. Let it go, the same way the
            # wizard lets go of every picture it loads.
            try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) } catch { }
        }

        # --- clear up anything we made before and are not making now --------
        foreach ($old in @(Get-LocalSetupRecord)) {
            if ($written -contains $old) { continue }
            if ([System.IO.Path]::GetExtension($old).ToLower() -ne '.lnk') { continue }
            if (-not (Test-Path -LiteralPath $old)) { continue }
            try { Remove-Item -LiteralPath $old -Force -ErrorAction Stop; $out.Results[$old] = 'removed' }
            catch { $out.Results[$old] = ("could not remove: " + $_.Exception.Message) }
        }

        # --- remember what we made ------------------------------------------
        try {
            $lines = @(
                '# Written by _ClaudeWorkspace\scripts\LocalSetup.ps1.',
                '# Every shortcut this computer was given, one per line. If a line here',
                '# is not written again the shortcut is removed, so renaming the drive',
                '# leaves nothing stranded on the Start Menu.',
                '# Delete this file and the folder around it to undo everything, or run',
                '# Set Up This Computer.bat and choose Remove.'
            ) + $written
            [System.IO.File]::WriteAllLines((Join-Path $icons $script:LocalMarkerFile), $lines,
                                            (New-Object System.Text.UTF8Encoding($false)))
        }
        catch { Note ("local setup: could not save the record - {0}" -f $_.Exception.Message) }

        foreach ($k in @($out.Results.Keys)) { Note ("local setup: {0} -> {1}" -f $k, $out.Results[$k]) }
    }
    catch {
        $out.Problem = $_.Exception.Message
        Note ("local setup: failed, carrying on - {0}" -f $_.Exception.Message)
    }

    return $out
}


# Refresh what is already there, and do NOTHING on a computer that has never
# been set up. This is what the wizard calls on every run: the drive gets a
# different letter on every machine, so a shortcut written last week points
# at the wrong place today, and the fix is simply to write it again with the
# path the drive has right now.
function Update-LocalSetup {
    [CmdletBinding()]
    param(
        [string]      $Root       = '',
        [string]      $WizardName = 'RetroBat',
        [scriptblock] $Logger     = $null
    )

    if (-not (Test-LocalSetupInstalled)) { return @{ Folder = ''; Results = @{}; StartMenu = ''; Problem = 'not set up on this computer' } }

    # Which places were used last time, so a refresh never quietly adds a
    # desktop icon nobody asked for.
    $places = @(Get-LocalSetupPlaces -WizardName $WizardName)
    if ($places.Count -eq 0) { $places = @('start') }

    return (Install-LocalSetup -Root $Root -WizardName $WizardName -Places $places -Logger $Logger)
}


# ---------------------------------------------------------------------------
#  Where this computer's buttons are RIGHT NOW: 'start', 'desktop', both, or
#  nothing at all. Read from the record of what was written, not by looking
#  for files, because a shortcut somebody dragged somewhere else is still
#  ours and still gets cleared up when it is no longer wanted.
#
#  This is what lets the wizard show the two switches already ticked the way
#  the computer actually is, rather than asking the same question from
#  scratch every time.
# ---------------------------------------------------------------------------
function Get-LocalSetupPlaces {
    [CmdletBinding()]
    param([string] $WizardName = 'RetroBat')

    $places = @()
    $start  = Get-StartMenuFolder -DriveName $WizardName
    $desk   = Get-DesktopFolder
    foreach ($p in @(Get-LocalSetupRecord)) {
        $d = ''
        try { $d = Split-Path $p -Parent } catch { }
        if ($start -ne '' -and $d -eq $start) { $places += 'start' }
        if ($desk  -ne '' -and $d -eq $desk)  { $places += 'desktop' }
    }
    return @($places | Select-Object -Unique)
}


# Undo. Removes every shortcut recorded, then the local folder itself.
function Remove-LocalSetup {
    [CmdletBinding()]
    param([scriptblock] $Logger = $null)

    $out = @{ Removed = @(); Problem = '' }

    function Note([string]$m) {
        if ($null -ne $Logger) { try { & $Logger $m } catch { } }
    }

    try {
        foreach ($p in @(Get-LocalSetupRecord)) {
            if ([System.IO.Path]::GetExtension($p).ToLower() -ne '.lnk') { continue }
            if (-not (Test-Path -LiteralPath $p)) { continue }
            try { Remove-Item -LiteralPath $p -Force -ErrorAction Stop; $out.Removed += $p } catch { }
        }

        # The Start Menu folder, but only if it is now empty. Never delete a
        # folder somebody else put something in.
        $start = ''
        foreach ($p in @($out.Removed)) {
            try { $d = Split-Path $p -Parent } catch { continue }
            if ($d -like '*\Start Menu\Programs\*') { $start = $d }
        }
        if ($start -ne '' -and (Test-Path -LiteralPath $start)) {
            $left = @(Get-ChildItem -LiteralPath $start -Force -ErrorAction SilentlyContinue)
            if ($left.Count -eq 0) { try { Remove-Item -LiteralPath $start -Force -ErrorAction Stop } catch { } }
        }

        $f = Get-LocalSetupFolder
        if ($f -ne '' -and (Test-Path -LiteralPath $f)) {
            try { Remove-Item -LiteralPath $f -Recurse -Force -ErrorAction Stop } catch { }
        }
        Note ("local setup: removed {0} shortcuts" -f @($out.Removed).Count)
    }
    catch {
        $out.Problem = $_.Exception.Message
        Note ("local setup: remove failed - {0}" -f $_.Exception.Message)
    }

    return $out
}
