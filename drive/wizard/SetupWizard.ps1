<#
    SetupWizard.ps1
    ---------------------------------------------------------------------------
    The front end. Two ways in, both .bat files at the DRIVE ROOT:

        PLAY.bat                         runs this with -Play: silent checks,
                                         a window only if something needs a
                                         decision, then RetroBat launches
        Steven the Setup Wizard.bat      opens the full window on purpose

    Tabs: Play, Health, Profiles, Saves, Features, Help. Saves (added 2026-08-29)
    is a window over SaveBackups\ and shares scripts\SaveIndex.ps1 with the
    SaveBackups\Browse My Saves.bat button. Features (added 2026-08-31) is a
    window over _ClaudeWorkspace\features.ini and shares scripts\Features.ps1
    with the Maintenance Steps\Show My Features.bat button.

    The window is a convenience layer over the engines that already exist -
    it reads _ClaudeWorkspace\status.json (written by Check-DriveHealth.ps1)
    and the profile system, and its Fix buttons run the same scripts the
    Maintenance Steps buttons run. If this window ever breaks, everything
    still works from those buttons.

    THE PLAY FLOW (-Play):
      1. RetroBat already running?            -> do nothing, it is on screen
      2. RetroBat's version changed since     -> "Putting your settings back"
         last launch (a RetroBat update)?        runs the six repair steps
      3. New computer with no profile?        -> offer the detected tier
         Profile applied for another machine? -> offer to switch
      4. Anything RED in the health check?    -> say so, offer Fix / Play anyway
      5. Launch RetroBat.
    When nothing needs a decision, no window appears at all.

    Everything is logged to _ClaudeWorkspace\wizard\wizard.log, because the
    .bat launches this with a hidden console - without the log, a failure
    here would be invisible (the exact silent-failure trap the customization
    record warns about).

    Help (added 2026-09-02, Phase 7) is a window over scripts\HelpText.ps1,
    which is also what Maintenance Steps\Show Help.bat prints. The Play tab
    was rebuilt at the same time: the drive's own logo and name at the top,
    an 8-bit Play button in the middle, and ONE summary light instead of
    seven. The seven did not go anywhere - they are the Health tab, which is
    unchanged. Seven lights on the front page was seven things to read
    before pressing a button.

    Every run also rebuilds the two icon shortcuts at the top level of the
    drive, through scripts\Shortcuts.ps1. Nothing is shipped and no drive
    letter is stored: they are built pointing at wherever the drive is right
    now. See that file for why.

    RULES HONOURED: no drive letters (everything derives from this file's
    location), no $PSScriptRoot inside param(), Windows PowerShell 5.1 only.
#>

[CmdletBinding()]
param(
    [switch]$Play,
    [switch]$Setup,
    # -Pad: opened by SELECT + START on a controller (PadWatch.ps1). Opens
    # full screen with the controller hints showing. Added 2026-09-23.
    [switch]$Pad
)

$ErrorActionPreference = 'Stop'

# --- locate RetroBat (wizard lives in <RetroBat>\_ClaudeWorkspace\wizard) --
$WizardDir = $PSScriptRoot
$Ws        = Split-Path $WizardDir -Parent
$Root      = Split-Path $Ws -Parent
$ScriptsDir = Join-Path $Ws 'scripts'
$LogPath    = Join-Path $WizardDir 'wizard.log'

function Log([string]$msg) {
    try {
        $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
        [System.IO.File]::AppendAllText($LogPath, $line + [Environment]::NewLine)
    } catch { }
}

try {

if (-not (Test-Path (Join-Path $Root 'retrobat.ini'))) {
    Log "FATAL: retrobat.ini not found above $WizardDir"
    exit 1
}

Add-Type -AssemblyName PresentationFramework

# ===========================================================================
#  THE LOADING SPLASH
# ===========================================================================
#  Every way into this drive - PLAY, the wizard icon, SETUP RETROBAT - starts
#  a PowerShell script through a hidden console, and PowerShell itself takes
#  about a second to start before a single line of this file runs. For that
#  second a click looks like it did nothing, which is exactly the complaint
#  this answers.
#
#  So this is deliberately the FIRST thing after WPF loads, before any file is
#  read, any profile resolved or any check run. It shows the drive's own
#  wordmark on a small borderless window, the way Word shows its logo, and
#  Close-Splash takes it away again the moment there is something real to look
#  at.
#
#  IT CAN NEVER BE THE PROBLEM. Every part is wrapped: no wordmark.png means
#  the name as text, a failure anywhere means no splash at all, and
#  Close-Splash is safe to call as many times as you like from anywhere. A
#  drive that cannot draw its own logo still plays games.
#
#  It is Topmost because it is worth nothing behind another window, and
#  ShowInTaskbar is off because it is not a thing you switch to.
# ---------------------------------------------------------------------------
$script:splash = $null

function Show-Splash {
    if ($null -ne $script:splash) { return }
    try {
        $w = New-Object System.Windows.Window
        $w.WindowStyle = 'None'
        $w.ResizeMode  = 'NoResize'
        $w.AllowsTransparency = $true
        $w.Background  = [System.Windows.Media.Brushes]::Transparent
        $w.ShowInTaskbar = $false
        $w.Topmost = $true
        $w.WindowStartupLocation = 'CenterScreen'
        $w.SizeToContent = 'WidthAndHeight'

        $b = New-Object System.Windows.Controls.Border
        $b.Background = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.Color]::FromRgb(27, 27, 34))
        $b.BorderBrush = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.Color]::FromRgb(58, 58, 72))
        $b.BorderThickness = New-Object System.Windows.Thickness(2)
        $b.Padding = New-Object System.Windows.Thickness(34, 26, 34, 22)

        $stack = New-Object System.Windows.Controls.StackPanel
        $stack.HorizontalAlignment = 'Center'

        $shown = $false
        $markPath = Join-Path $WizardDir 'wordmark.png'
        if (Test-Path -LiteralPath $markPath) {
            try {
                $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
                $bmp.BeginInit()
                $bmp.UriSource = New-Object System.Uri($markPath)
                # OnLoad like every picture here: without it WPF holds the file
                # open, and a drive with an open file on it will not eject.
                $bmp.CacheOption = 'OnLoad'
                $bmp.EndInit()
                $img = New-Object System.Windows.Controls.Image
                $img.Source = $bmp
                $img.Stretch = 'None'
                [System.Windows.Media.RenderOptions]::SetBitmapScalingMode(
                    $img, [System.Windows.Media.BitmapScalingMode]::NearestNeighbor)
                [void]$stack.Children.Add($img)
                $shown = $true
            }
            catch { }
        }
        if (-not $shown) {
            $t = New-Object System.Windows.Controls.TextBlock
            $t.Text = 'Loading...'
            $t.FontSize = 22
            $t.FontWeight = 'Bold'
            $t.HorizontalAlignment = 'Center'
            $t.Foreground = New-Object System.Windows.Media.SolidColorBrush(
                [System.Windows.Media.Color]::FromRgb(232, 232, 236))
            [void]$stack.Children.Add($t)
        }

        $sub = New-Object System.Windows.Controls.TextBlock
        $sub.Text = 'Loading...'
        $sub.FontSize = 13
        $sub.Margin = New-Object System.Windows.Thickness(0, 14, 0, 0)
        $sub.HorizontalAlignment = 'Center'
        $sub.Foreground = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.Color]::FromRgb(154, 160, 170))
        [void]$stack.Children.Add($sub)

        $b.Child = $stack
        $w.Content = $b
        $w.Show()
        # Paint it NOW. Without this the window exists but stays blank until
        # the thread next goes idle, which is after all the slow work - the
        # one thing this must not do.
        $w.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Render)
        $script:splash = $w
    }
    catch { $script:splash = $null }
}

# Safe to call from anywhere, as often as you like, including twice.
function Close-Splash {
    if ($null -eq $script:splash) { return }
    try { $script:splash.Close() } catch { }
    $script:splash = $null
}

Show-Splash

# --- wizard config and state -----------------------------------------------
# --- the on/off switches ---------------------------------------------------
#  Loaded once, guarded. If Features.ps1 is missing the window still opens
#  and the Features tab simply says so - it never takes the whole wizard
#  down, and every feature stays ON, which is what this drive did before the
#  switches existed.
$script:featuresOk = $false
$featuresLib = Join-Path $ScriptsDir 'Features.ps1'
if (Test-Path -LiteralPath $featuresLib) {
    try { . $featuresLib; $script:featuresOk = $true }
    catch { Log "could not load Features.ps1: $_" }
}
else { Log 'Features.ps1 not found - the Features tab will be empty' }

# --- the Help page, and the drive-root shortcuts ---------------------------
#  Both are loaded the same guarded way as Features.ps1 above: if the file
#  is missing the window still opens, the Help tab simply says where to read
#  instead, and no shortcuts get built. Neither can take the wizard down.
$script:helpOk = $false
$helpLib = Join-Path $ScriptsDir 'HelpText.ps1'
if (Test-Path -LiteralPath $helpLib) {
    try { . $helpLib; $script:helpOk = $true }
    catch { Log "could not load HelpText.ps1: $_" }
}
else { Log 'HelpText.ps1 not found - the Help tab will point at the docs' }

$script:shortcutsOk = $false
$shortcutLib = Join-Path $ScriptsDir 'Shortcuts.ps1'
if (Test-Path -LiteralPath $shortcutLib) {
    try { . $shortcutLib; $script:shortcutsOk = $true }
    catch { Log "could not load Shortcuts.ps1: $_" }
}
else { Log 'Shortcuts.ps1 not found - the drive-root icons will not be built' }

$script:localSetupOk = $false
$localLib = Join-Path $ScriptsDir 'LocalSetup.ps1'
if (Test-Path -LiteralPath $localLib) {
    try { . $localLib; $script:localSetupOk = $true }
    catch { Log "could not load LocalSetup.ps1: $_" }
}
else { Log 'LocalSetup.ps1 not found - the Set up this computer button will be hidden' }

# --- the SELECT + START controller shortcut (2026-09-23) --------------------
#  scripts\PadShortcut.ps1 turns it on or off for THIS computer. Guarded like
#  everything above: a missing file just means no switch and no question.
#  (The part that lets a controller drive this window, PadInput.ps1, loads
#  later, after the window is on screen - see Start-PadNav.)
$script:padShortcutOk = $false
$padLib = Join-Path $ScriptsDir 'PadShortcut.ps1'
if (Test-Path -LiteralPath $padLib) {
    try { . $padLib; $script:padShortcutOk = $true }
    catch { Log "could not load PadShortcut.ps1: $_" }
}
$script:padLaunch = [bool]$Pad

# --- the Steam system ------------------------------------------------------
#  Two files, loaded together or not at all: the engine is no use without a
#  window and the window is no use without the engine. Guarded the same way
#  as everything above, so a missing pair means the Steam section simply does
#  not appear on the Machine tab and the wizard is otherwise untouched.
$script:steamOk = $false
$steamLib   = Join-Path $ScriptsDir 'SteamEngine.ps1'
$steamUiLib = Join-Path $ScriptsDir 'SteamUI.ps1'
if ((Test-Path -LiteralPath $steamLib) -and (Test-Path -LiteralPath $steamUiLib)) {
    try { . $steamLib; . $steamUiLib; $script:steamOk = $true }
    catch { Log "could not load the Steam scripts: $_" }
}
else { Log 'SteamEngine.ps1 or SteamUI.ps1 not found - the Steam section will be hidden' }

# --- the game shortcut maker -----------------------------------------------
#  Same guarded pair as the Steam scripts: engine plus window, both or
#  neither, and a failure only costs the one button on the Help tab.
$script:shortcutMakerOk = $false
$scMakerLib = Join-Path $ScriptsDir 'ShortcutMaker.ps1'
$scMakerUi  = Join-Path $ScriptsDir 'ShortcutMakerUI.ps1'
if ((Test-Path -LiteralPath $scMakerLib) -and (Test-Path -LiteralPath $scMakerUi)) {
    try { . $scMakerLib; . $scMakerUi; $script:shortcutMakerOk = $true }
    catch { Log "could not load the shortcut maker: $_" }
}
else { Log 'ShortcutMaker.ps1 or ShortcutMakerUI.ps1 not found - the game shortcut button will be hidden' }

# --- one-time renames, and the updater (2026-10-10) -------------------------
#  Migrations.ps1 holds every one-time change to the SHAPE of the drive (the
#  first: profiles\ became machine\). The updater runs it with a journal before
#  installing an update; this is the safety net for a drive whose files were
#  copied over by hand. It runs in every mode, PLAY included, before anything
#  reads those folders. It is a rename the drive does to itself once, not a
#  thing put on the computer, and on a drive that is already in shape it
#  checks two paths and does nothing.
$migLib = Join-Path $ScriptsDir 'Migrations.ps1'
if (Test-Path -LiteralPath $migLib) {
    try { . $migLib; [void]@(Invoke-DriveMigrations -Ws $Ws -Logger { param($m) Log $m }) }
    catch { Log "migrations: $_" }
}

#  UpdateEngine.ps1 is the updater. Guarded like everything above: without it
#  there is simply no update bar and no update buttons.
$script:updateOk = $false
$script:updLib = Join-Path $ScriptsDir 'UpdateEngine.ps1'
if (Test-Path -LiteralPath $script:updLib) {
    try { . $script:updLib; $script:updateOk = $true }
    catch { Log "could not load UpdateEngine.ps1: $_" }
}
else { Log 'UpdateEngine.ps1 not found - updates are switched off' }

#  SocialEngine.ps1 is the Profile tab: who is using the drive, friends, and
#  what they are playing. Guarded the same way: without it the tab says so.
$script:socialOk = $false
$script:socialLib = Join-Path $ScriptsDir 'SocialEngine.ps1'
if (Test-Path -LiteralPath $script:socialLib) {
    try { . $script:socialLib; $script:socialOk = $true }
    catch { Log "could not load SocialEngine.ps1: $_" }
}
else { Log 'SocialEngine.ps1 not found - the Profile tab will be empty' }

#  AdminEngine.ps1 is the Admin tab, shown only to people on the admins list
#  in the private repo (Steven, 2026-10-10). It needs SocialEngine.ps1.
$script:adminOk = $false
$adminLib = Join-Path $ScriptsDir 'AdminEngine.ps1'
if ($script:socialOk -and (Test-Path -LiteralPath $adminLib)) {
    try { . $adminLib; $script:adminOk = $true }
    catch { Log "could not load AdminEngine.ps1: $_" }
}

#  GameLibrary.ps1 is the Games tab: add a game, the online library.
$script:gamesOk = $false
$gamesLib = Join-Path $ScriptsDir 'GameLibrary.ps1'
if (Test-Path -LiteralPath $gamesLib) {
    try { . $gamesLib; $script:gamesOk = $true }
    catch { Log "could not load GameLibrary.ps1: $_" }
}
else { Log 'GameLibrary.ps1 not found - the Games tab will be empty' }

#  NetplayEngine.ps1 is the Netplay tab.
$script:netplayOk = $false
$netplayLib = Join-Path $ScriptsDir 'NetplayEngine.ps1'
if (Test-Path -LiteralPath $netplayLib) {
    try { . $netplayLib; $script:netplayOk = $true }
    catch { Log "could not load NetplayEngine.ps1: $_" }
}
else { Log 'NetplayEngine.ps1 not found - the Netplay tab will be empty' }

#  BugReport.ps1 needs SocialEngine.ps1 (same token, same way to GitHub).
$script:bugOk = $false
$script:bugLib = Join-Path $ScriptsDir 'BugReport.ps1'
if ($script:socialOk -and (Test-Path -LiteralPath $script:bugLib)) {
    try { . $script:bugLib; $script:bugOk = $true }
    catch { Log "could not load BugReport.ps1: $_" }
}

# --- the drive letter ------------------------------------------------------
#  A CONVENIENCE ONLY. Nothing on this drive may depend on being R:, and
#  nothing does - every script still works out where it is from its own
#  location. This exists for the stray letter that creeps into an emulator's
#  own config file, not as a foundation.
$script:driveLetterOk = $false
$driveLetterLib = Join-Path $ScriptsDir 'DriveLetter.ps1'
if (Test-Path -LiteralPath $driveLetterLib) {
    try { . $driveLetterLib; $script:driveLetterOk = $true }
    catch { Log "could not load DriveLetter.ps1: $_" }
}
else { Log 'DriveLetter.ps1 not found - the drive letter offer will be hidden' }

function Read-KeyValues([string]$Path) {
    $out = @{}
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
            $t = $line.Trim()
            if ($t -eq '' -or $t.StartsWith(';') -or $t.StartsWith('#')) { continue }
            $eq = $t.IndexOf('=')
            if ($eq -lt 1) { continue }
            $out[$t.Substring(0, $eq).Trim()] = $t.Substring($eq + 1).Trim()
        }
    }
    return $out
}

$cfg = Read-KeyValues (Join-Path $WizardDir 'wizard.ini')
$WizardName    = if ($cfg['name'])    { $cfg['name'] }    else { 'Setup Wizard' }
# The version lives in _ClaudeWorkspace\version.txt since 2026-10-10, because
# an update replaces that file and must never touch wizard.ini, which is the
# owner's (it holds the drive's name). A drive from before then still has a
# version line in wizard.ini, which is read only when version.txt is missing.
$WizardVersion = ''
$verFile = Join-Path $Ws 'version.txt'
if (Test-Path -LiteralPath $verFile) {
    foreach ($vl in [System.IO.File]::ReadAllLines($verFile)) {
        $vt = $vl.Trim()
        if ($vt -ne '' -and -not $vt.StartsWith(';') -and -not $vt.StartsWith('#')) { $WizardVersion = $vt; break }
    }
}
if ($WizardVersion -eq '') { $WizardVersion = if ($cfg['version']) { $cfg['version'] } else { '?' } }

$StatePath = Join-Path $WizardDir 'state.ini'

function Get-RetroBatVersion {
    $vf = Join-Path $Root 'system\version.info'
    if (Test-Path -LiteralPath $vf) { return ([System.IO.File]::ReadAllText($vf)).Trim() }
    return ''
}

# --- colours and small UI helpers ------------------------------------------
$ColBg     = '#FF1B1B22'; $ColPanel = '#FF23232C'; $ColText = '#FFE8E8EC'
$ColDim    = '#FF9AA0AA'
$StatusColour = @{ ok = '#FF2FA84F'; warn = '#FFE5B83B'; bad = '#FFE0524D'; unknown = '#FF777777' }

function New-Brush([string]$hex) {
    (New-Object System.Windows.Media.BrushConverter).ConvertFromString($hex)
}

function New-Text([string]$text, [string]$colour, [double]$size, [bool]$bold = $false) {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $text; $tb.Foreground = (New-Brush $colour); $tb.FontSize = $size
    $tb.TextWrapping = 'Wrap'
    if ($bold) { $tb.FontWeight = 'Bold' }
    return $tb
}

# A small dark dialog with custom buttons. Returns the clicked label, or ''
# if the window was just closed.
function Show-Choice([string]$Title, [string]$Message, [string[]]$Buttons) {
    # Nothing should ever have to be read from behind the loading splash.
    Close-Splash
    $w = New-Object System.Windows.Window
    $w.Title = $Title; $w.Width = 480; $w.SizeToContent = 'Height'
    $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'NoResize'
    $w.Background = (New-Brush $ColBg); $w.Topmost = $true
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = '22'
    $msg = New-Text $Message $ColText 15
    $msg.Margin = '0,0,0,18'
    [void]$sp.Children.Add($msg)
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.HorizontalAlignment = 'Right'
    # The clicked label lands in a script-scope variable. Event handler
    # scriptblocks cannot be trusted to see function locals or closures
    # reliably in Windows PowerShell, so everything they touch is either the
    # sender ($args[0]) or script scope.
    $script:choiceResult = ''
    $script:choiceWin    = $w
    foreach ($label in $Buttons) {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $label; $b.Margin = '8,0,0,0'; $b.Padding = '16,7'
        $b.FontSize = 14; $b.Tag = $label
        $b.Add_Click({ param($s, $e) $script:choiceResult = [string]$s.Tag; $script:choiceWin.Close() })
        [void]$row.Children.Add($b)
    }
    [void]$sp.Children.Add($row)
    $w.Content = $sp
    [void]$w.ShowDialog()
    return $script:choiceResult
}

# ===========================================================================
#  WHERE THIS COMPUTER'S BUTTONS GO - two switches, not a row of buttons
# ===========================================================================
#  This used to be a Show-Choice with "Start Menu" and "Start Menu and
#  desktop" as separate buttons, which made four possible answers reachable
#  through three buttons and left "desktop only" unreachable entirely.
#
#  Two switches say the same thing honestly: each place is on or off, all
#  four combinations exist, and turning both off is a real answer that means
#  "take them away again". The line underneath says out loud what pressing
#  Save is about to do, because "both off" is the one combination somebody
#  could tick by accident.
#
#  Returns a hashtable: Ok ($false if cancelled) and Places, an array of
#  'start' and/or 'desktop'.
# ---------------------------------------------------------------------------
function Show-PlaceToggles([string]$Title, [string]$Message, [string[]]$Current) {
    Close-Splash

    $w = New-Object System.Windows.Window
    $w.Title = $Title; $w.Width = 500; $w.SizeToContent = 'Height'
    $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'NoResize'
    $w.Background = (New-Brush $ColBg); $w.Topmost = $true

    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = '22'
    $msg = New-Text $Message $ColText 15
    $msg.Margin = '0,0,0,16'
    [void]$sp.Children.Add($msg)

    $cbStart = New-Object System.Windows.Controls.CheckBox
    $cbStart.Content = 'Start Menu'
    $cbStart.Foreground = (New-Brush $ColText); $cbStart.FontSize = 15
    $cbStart.IsChecked = ([string[]]$Current -contains 'start')

    $cbDesk = New-Object System.Windows.Controls.CheckBox
    $cbDesk.Content = 'Desktop'
    $cbDesk.Foreground = (New-Brush $ColText); $cbDesk.FontSize = 15
    $cbDesk.Margin = '0,10,0,0'
    $cbDesk.IsChecked = ([string[]]$Current -contains 'desktop')

    [void]$sp.Children.Add($cbStart)
    [void]$sp.Children.Add($cbDesk)

    $note = New-Text '' $ColDim 13
    $note.Margin = '0,14,0,0'; $note.TextWrapping = 'Wrap'
    [void]$sp.Children.Add($note)

    # Script scope for the same reason Show-Choice uses it: an event handler
    # in Windows PowerShell cannot be relied on to see a function's locals.
    $script:placeStart = $cbStart
    $script:placeDesk  = $cbDesk
    $script:placeNote  = $note
    $script:placeOk    = $false
    $script:placeWin   = $w

    $cbStart.Add_Click({ Update-PlaceNote })
    $cbDesk.Add_Click({ Update-PlaceNote })
    Update-PlaceNote

    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.HorizontalAlignment = 'Right'
    $row.Margin = '0,18,0,0'
    $cancel = New-Object System.Windows.Controls.Button
    $cancel.Content = 'Cancel'; $cancel.Padding = '16,7'; $cancel.FontSize = 14
    $cancel.Add_Click({ $script:placeOk = $false; $script:placeWin.Close() })
    $save = New-Object System.Windows.Controls.Button
    $save.Content = 'Save'; $save.Padding = '16,7'; $save.FontSize = 14; $save.Margin = '8,0,0,0'
    $save.Add_Click({ $script:placeOk = $true; $script:placeWin.Close() })
    [void]$row.Children.Add($cancel)
    [void]$row.Children.Add($save)
    [void]$sp.Children.Add($row)

    $w.Content = $sp
    [void]$w.ShowDialog()

    $places = @()
    if ($script:placeStart.IsChecked) { $places += 'start' }
    if ($script:placeDesk.IsChecked)  { $places += 'desktop' }
    return @{ Ok = $script:placeOk; Places = $places }
}

# Says out loud what Save is about to do. Top level, not a closure, because
# the two Add_Click handlers above have to be able to find it.
function Update-PlaceNote {
    if ($null -eq $script:placeNote) { return }
    $st = [bool]$script:placeStart.IsChecked
    $dk = [bool]$script:placeDesk.IsChecked
    if     ($st -and $dk) { $script:placeNote.Text = 'Save puts Play, this wizard and a Controllers button in both places.' }
    elseif ($st)          { $script:placeNote.Text = 'Save puts Play, this wizard and a Controllers button on the Start Menu only.' }
    elseif ($dk)          { $script:placeNote.Text = 'Save puts Play, this wizard and a Controllers button on the desktop only.' }
    else                  { $script:placeNote.Text = 'Both switched off: Save takes this computer''s buttons away again. The drive itself is untouched and still works.' }
}


# A list to pick from, with a way out to typing it yourself. Show-Choice is a
# row of buttons, which is right for three options and useless for fifty.
#
# Returns the chosen item, a single '?' for "let me type it instead", or an
# empty string for cancel. Everything the handlers touch is either the sender
# or script scope, for the same reason Show-Choice does it that way.
function Show-ListPick([string]$Title, [string]$Message, [string[]]$Items) {
    Close-Splash
    $w = New-Object System.Windows.Window
    $w.Title = $Title; $w.Width = 540; $w.Height = 480
    $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'NoResize'
    $w.Background = (New-Brush $ColBg); $w.Topmost = $true

    $dp = New-Object System.Windows.Controls.DockPanel
    $dp.Margin = '20'

    $msg = New-Text $Message $ColText 14
    $msg.Margin = '0,0,0,12'
    [System.Windows.Controls.DockPanel]::SetDock($msg, 'Top')
    [void]$dp.Children.Add($msg)

    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.HorizontalAlignment = 'Right'; $row.Margin = '0,14,0,0'
    [System.Windows.Controls.DockPanel]::SetDock($row, 'Bottom')

    $script:pickResult = ''
    $script:pickWin    = $w

    $lb = New-Object System.Windows.Controls.ListBox
    $lb.FontSize = 13
    foreach ($i in @($Items)) { [void]$lb.Items.Add([string]$i) }
    if ($lb.Items.Count -gt 0) { $lb.SelectedIndex = 0 }
    $script:pickList = $lb
    $lb.Add_MouseDoubleClick({
        $sel = $script:pickList.SelectedItem
        if ($null -ne $sel) { $script:pickResult = [string]$sel; $script:pickWin.Close() }
    })

    foreach ($pair in @(@('Use this name', 'ok'), @('Type it myself', '?'), @('Cancel', 'x'))) {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $pair[0]; $b.Margin = '8,0,0,0'; $b.Padding = '16,7'; $b.FontSize = 14
        $b.Tag = $pair[1]
        $b.Add_Click({
            param($s, $e)
            $t = [string]$s.Tag
            if ($t -eq 'ok') {
                $sel = $script:pickList.SelectedItem
                if ($null -eq $sel) { $script:pickResult = '' } else { $script:pickResult = [string]$sel }
            }
            elseif ($t -eq '?') { $script:pickResult = '?' }
            else                { $script:pickResult = '' }
            $script:pickWin.Close()
        })
        [void]$row.Children.Add($b)
    }

    [void]$dp.Children.Add($row)
    # Added last, with no Dock set, so it fills whatever is left over.
    [void]$dp.Children.Add($lb)

    $w.Content = $dp
    [void]$w.ShowDialog()
    return $script:pickResult
}

# --- engines ----------------------------------------------------------------
. (Join-Path $ScriptsDir 'ProfileEngine.ps1')
# The saves engine, shared with SaveBackups\Browse My Saves.bat so that button
# and this window can never disagree about what counts as a game.
. (Join-Path $ScriptsDir 'SaveIndex.ps1')
# Works out what a game code really is, and finds its box art, from the game
# files and gamelist.xml files already on this drive.
. (Join-Path $ScriptsDir 'GameNames.ps1')
# The hand-checked game lists (player counts, controllers, collections).
# Guarded like the Steam pair: if either file is missing, the Controllers
# row on the Machine tab simply does not appear and PLAY skips that step.
$script:gameInfoOk = $false
try {
    $pcLibTop = Join-Path $ScriptsDir 'PlayerCounts.ps1'
    $giLibTop = Join-Path $ScriptsDir 'GameInfo.ps1'
    if (Test-Path -LiteralPath $pcLibTop) { . $pcLibTop }
    if (Test-Path -LiteralPath $giLibTop) { . $giLibTop; $script:gameInfoOk = $true }
}
catch { Log "could not load the game list scripts: $_" }

function Test-RetroBatRunning {
    $p = Get-Process -Name 'emulationstation', 'RetroBat', 'BatGui' -ErrorAction SilentlyContinue
    return ($null -ne $p)
}

# Runs another of our scripts, captures everything it prints into the log,
# returns its exit code.
function Invoke-Step([string]$ScriptName, [string]$FriendlyName, [hashtable]$NamedArgs = @{}) {
    $p = Join-Path $ScriptsDir $ScriptName
    if (-not (Test-Path -LiteralPath $p)) { Log "step '$FriendlyName': $ScriptName not found"; return 1 }
    Log "step '$FriendlyName' starting"
    $global:LASTEXITCODE = 0
    # Hashtable splatting: an ARRAY splat would hand "-Quiet" over as a
    # positional argument instead of a switch, which is exactly the
    # "positional parameter cannot be found" error seen on 2026-08-27.
    #
    # The try/catch matters: these scripts inherit $ErrorActionPreference
    # = 'Stop', so one of them throwing would otherwise sail straight past
    # this function and kill the whole wizard in the middle of a repair. A
    # step that dies is a failed step, not a dead window.
    $out  = ''
    $code = 0
    try {
        $out  = & $p @NamedArgs *>&1 | Out-String
        $code = $LASTEXITCODE
    }
    catch {
        $code = 1
        Log ("step '$FriendlyName' threw: {0}" -f $_.Exception.Message)
    }
    if ($null -eq $code) { $code = 0 }
    Log ("step '$FriendlyName' finished, exit code {0}" -f $code)
    if ($out) { Log ($out.TrimEnd()) }
    return $code
}

function Invoke-Health {
    [void](Invoke-Step 'Check-DriveHealth.ps1' 'health check' @{ Quiet = $true })
    $sp = Join-Path $Ws 'status.json'
    if (Test-Path -LiteralPath $sp) {
        return (Get-Content -LiteralPath $sp -Raw | ConvertFrom-Json)
    }
    return $null
}

# --- RetroBat update auto-repair -------------------------------------------
# The six steps of RUN THIS AFTER AN UPDATE, run quietly with a progress
# window. Only triggered when system\version.info changes between launches.
function Invoke-UpdateRepair([string]$newVersion) {
    # This has a progress window of its own, which says more than the splash.
    Close-Splash
    $w = New-Object System.Windows.Window
    $w.Title = $WizardName; $w.Width = 470; $w.Height = 150
    $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'NoResize'
    $w.Background = (New-Brush $ColBg); $w.Topmost = $true
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '22'
    $head = New-Text ("RetroBat updated to {0}." -f $newVersion) $ColText 15 $true
    $line = New-Text 'Putting your settings back...' $ColDim 14
    $line.Margin = '0,10,0,0'
    [void]$sp.Children.Add($head); [void]$sp.Children.Add($line)
    $w.Content = $sp
    $w.Show()
    function Update-Line([string]$t) {
        $line.Text = $t
        $w.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Render)
    }

    $steps = @(
        @('Restore-ProtectedFiles.ps1',  'putting protected files back'),
        @('Fix-Portability.ps1',         'fixing drive letters'),
        @('Apply-Settings.ps1',          'applying your settings'),
        @('Restore-CkauBookTheme.ps1',   'restoring theme collections'),
        @('Decompress-3DS.ps1',          'checking for new 3DS games'),
        @('Fix-VideoVolume.ps1',         'levelling video volume')
    )
    $failed = @()
    $n = 0
    foreach ($s in $steps) {
        $n++
        Update-Line ("Step {0} of {1}: {2}..." -f $n, $steps.Count, $s[1])
        $code = Invoke-Step $s[0] $s[1]
        if ($code -ne 0) { $failed += $s[1] }
    }
    $w.Close()
    return $failed
}

# --- profile helpers --------------------------------------------------------
function Set-ProfileTier([string]$ProfileFile, [string]$Tier) {
    $lines = @([System.IO.File]::ReadAllLines($ProfileFile))
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $t = $lines[$i].Trim()
        # skip comments: these files are full of explanation, and a commented
        # example line mentioning "tier =" must not be mistaken for the setting
        if ($t.StartsWith(';') -or $t.StartsWith('#')) { continue }
        if ($t -match '^\s*tier\s*=') { $lines[$i] = "tier    = $Tier"; break }
    }
    [System.IO.File]::WriteAllLines($ProfileFile, $lines, (New-Object System.Text.UTF8Encoding($false)))
}

# Handles the "new computer" and "wrong machine's profile" questions.
# Returns $true if settings were (re)applied.
function Resolve-ProfileQuestions {
    $mp = $null
    try { $mp = Resolve-MachineProfile -Root $Root -NoWrite } catch { Log "profile resolve failed: $_" }
    if ($null -eq $mp -or -not $mp.Ok) { return $false }

    if ($mp.Created) {
        $pick = Show-Choice $WizardName ("New computer: {0}`nGraphics card: {1}`n`nSuggesting the {2} tier." -f $mp.Machine, $mp.Gpu, $mp.Tier.ToUpper()) @("Use $($mp.Tier)", 'Pick another', 'Skip for now')
        if ($pick -eq 'Skip for now' -or $pick -eq '') { Log 'new computer: skipped'; return $false }
        $tier = $mp.Tier
        if ($pick -eq 'Pick another') {
            $t2 = Show-Choice $WizardName 'Pick a tier for this computer. Low favours smoothness, High favours picture quality. The Machine tab changes it later.' @('Low', 'Medium', 'High')
            if ($t2 -eq '') { return $false }
            $tier = $t2.ToLower()
        }
        # Apply once (this creates the profile with the detected tier), then
        # correct the tier if the user picked a different one and re-apply.
        [void](Invoke-Step 'Apply-Settings.ps1' 'applying settings (new computer)')
        if ($tier -ne $mp.Tier) {
            $mp2 = $null
            try { $mp2 = Resolve-MachineProfile -Root $Root -NoWrite } catch { }
            if ($mp2 -and $mp2.ProfileFile -and (Test-Path -LiteralPath $mp2.ProfileFile)) {
                Set-ProfileTier $mp2.ProfileFile $tier
                Log "tier changed to $tier by user choice"
                [void](Invoke-Step 'Apply-Settings.ps1' 'applying settings (chosen tier)')
            }
        }
        return $true
    }

    # existing machine: is the drive still carrying another machine's settings?
    $activePath = Join-Path $Ws 'machine\active.txt'
    if (Test-Path -LiteralPath $activePath) {
        $activeText = [System.IO.File]::ReadAllText($activePath)
        if ($activeText -match 'machine\s*=\s*(.+)') {
            $activeMachine = $Matches[1].Trim()
            if ($activeMachine -and ($activeMachine -ine $mp.Machine)) {
                $pick = Show-Choice $WizardName ("You are on {0}, but the settings on the drive were applied for {1}." -f $mp.Machine, $activeMachine) @("Switch to $($mp.ProfileName)", "Keep $activeMachine's settings")
                if ($pick -like 'Switch*') {
                    [void](Invoke-Step 'Apply-Settings.ps1' 'switching machine')
                    return $true
                }
            }
        }
    }
    return $false
}

# --- the Play flow ----------------------------------------------------------
function Start-PlayFlow {
    Log '--- Play flow ---'
    if (Test-RetroBatRunning) { Log 'RetroBat already running, nothing to do'; Close-Splash; return }

    # RetroBat update detection
    $cur = Get-RetroBatVersion
    $state = Read-KeyValues $StatePath
    $last = [string]$state['lastretrobatversion']
    if ($cur -ne '') {
        if ($last -eq '') {
            Log "first run, recording RetroBat version $cur"
            [System.IO.File]::WriteAllLines($StatePath, @("lastretrobatversion = $cur"), (New-Object System.Text.UTF8Encoding($false)))
        }
        elseif ($last -ne $cur) {
            Log "RetroBat version changed: $last -> $cur, running repair"
            # The @() matters. A PowerShell function that returns an EMPTY
            # array returns nothing at all, and $null.Count is not 0 - so
            # without it a repair where everything worked would be reported
            # as a failure, and the new version would never be recorded,
            # making the repair run again on every single launch.
            $failed = @(Invoke-UpdateRepair $cur)
            if ($failed.Count -eq 0) {
                [System.IO.File]::WriteAllLines($StatePath, @("lastretrobatversion = $cur"), (New-Object System.Text.UTF8Encoding($false)))
            }
            else {
                [void](Show-Choice $WizardName ("These repair steps had problems: {0}.`n`nRetroBat will still start. Run RUN THIS AFTER AN UPDATE.bat later, or check wizard.log." -f ($failed -join ', ')) @('OK'))
            }
        }
    }

    # profile questions (new computer / wrong machine)
    [void](Resolve-ProfileQuestions)

    # health check
    $status = Invoke-Health
    if ($status -and $status.overall -eq 'bad') {
        $firstBad = ''
        foreach ($p in $status.checks.PSObject.Properties) {
            if ($p.Value.status -eq 'bad') { $firstBad = "$($p.Value.title): $($p.Value.summary)"; break }
        }
        $pick = Show-Choice $WizardName ("Something needs attention:`n`n$firstBad") @('Open the wizard', 'Play anyway')
        if ($pick -eq 'Open the wizard') { Show-MainWindow $status 'health'; return }
    }

    # --- the Steam shelf, before RetroBat reads its game lists -------------
    #  THIS IS THE ONE THING PLAY WRITES, and it is a deliberate exception to
    #  "the everyday button writes nothing". It has to be here: the tiles live
    #  on the DRIVE but whether they should show is a fact about the COMPUTER,
    #  so plugging into somebody else's PC and pressing Play would otherwise
    #  hand them a shelf of games they cannot launch. Connect Steam alone
    #  cannot cover that, because on their computer it was never run.
    #
    #  It only ever touches roms\steam and only when the two disagree, it can
    #  never stop the launch, and on a computer with no [steam] section its
    #  whole job is to take tiles AWAY.
    if ($script:steamOk) {
        try {
            $steamSync = Sync-SteamSystem -Root $Root
            Log ('steam: ' + $steamSync.Message)
        }
        catch { Log ('steam: could not sync the shelf - ' + $_.Exception.Message) }
    }

    # --- the hand-checked game lists, also before RetroBat reads them ------
    #  Added 2026-09-25, for the same reason as the Steam shelf: it has to
    #  happen before the game lists are read. Three plain files in
    #  _ClaudeWorkspace are the boss, and this copies them in:
    #    player-counts.ini  the "players" number    (scripts\PlayerCounts.ps1)
    #    controllers.ini    a "Controllers:" line at the top of each Wii and
    #                       Wii U description, and the Wii U controller
    #                       settings                 (scripts\GameInfo.ps1)
    #    collections.ini    who is in the Zelda and Pokemon collections
    #  Each only writes a file where something disagrees, touches nothing
    #  else in it, and none of it can stop the launch. Games no list covers
    #  yet are written to _ClaudeWorkspace\new-games-to-check.txt.
    #  If the controller settings changed, Apply-Settings runs once so they
    #  reach RetroBat now rather than after the next update.
    try {
        if ($script:gameInfoOk) {
            $gi = Invoke-GameInfoSync -Root $Root
            foreach ($m in @($gi.Messages)) { Log ('game lists: ' + $m) }
            if ($gi.SettingsChanged) {
                Log 'game lists: controller settings changed, applying them'
                [void](Invoke-Step 'Apply-Settings.ps1' 'applying controller settings')
            }
        }
        elseif (Get-Command Sync-PlayerCounts -ErrorAction SilentlyContinue) {
            $pc = Sync-PlayerCounts -Root $Root
            Log ('player counts: ' + $pc.Message)
        }
        else { Log 'game lists: GameInfo.ps1 and PlayerCounts.ps1 not found, skipped' }
    }
    catch { Log ('game lists: could not apply - ' + $_.Exception.Message) }

    # --- ckau-book, once it has arrived (2026-10-10) --------------------------
    #  A fresh install asks friends to fetch the ckau-book theme through
    #  RetroBat's own downloader. The first PLAY after it lands switches to it,
    #  but only from RetroBat's stock theme, and only ONCE (state.ini
    #  remembers), so somebody who later picks another theme keeps it.
    if ($script:netplayOk) {
        try {
            $stv = Read-KeyValues $StatePath
            $themeXml = Join-Path $Root 'emulationstation\.emulationstation\themes\ckau-book\theme.xml'
            if ([string]$stv['ckaubookswitched'] -ne 'yes' -and (Test-Path -LiteralPath $themeXml)) {
                $esPath = Join-Path $Root 'emulationstation\.emulationstation\es_settings.cfg'
                $curTheme = ''
                $m = [regex]::Match([System.IO.File]::ReadAllText($esPath), '<string name="ThemeSet" value="([^"]*)"')
                if ($m.Success) { $curTheme = $m.Groups[1].Value }
                if ($curTheme -eq '' -or $curTheme -eq 'es-theme-carbon') {
                    if (Set-EsStringSetting $Root 'ThemeSet' 'ckau-book') { Log 'theme: switched to ckau-book' }
                }
                $lines = @()
                if (Test-Path -LiteralPath $StatePath) { $lines = @([System.IO.File]::ReadAllLines($StatePath) | Where-Object { $_ -notmatch '^\s*ckaubookswitched\s*=' }) }
                $lines += 'ckaubookswitched = yes'
                [System.IO.File]::WriteAllLines($StatePath, [string[]]$lines, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
        catch { Log ('theme: could not check for ckau-book - ' + $_.Exception.Message) }
    }

    # --- the netplay name follows the profile (2026-10-10) ------------------
    #  Same reason as above: es_settings.cfg can only be written while
    #  RetroBat is closed, and this is the last moment it is. One setting,
    #  only when it differs, and it can never stop the launch.
    if ($script:netplayOk) {
        try {
            $np = Get-NetplayWantedName
            if ($np -ne '' -and (Get-NetplaySettings $Root).Nickname -ne $np) {
                $r = Set-NetplaySettings $Root @{ Nickname = $np }
                Log ("netplay: name set to '{0}' ({1})" -f $np, $(if ($r.Ok) { 'ok' } else { $r.Message }))
            }
        }
        catch { Log ('netplay: could not set the name - ' + $_.Exception.Message) }
    }

    Log 'launching RetroBat'
    Close-Splash
    Start-Process -FilePath (Join-Path $Root 'RetroBat.exe') -WorkingDirectory $Root
}

# ===========================================================================
#  THE SETUP FLOW  (-Setup)   ...   SETUP RETROBAT.bat at the top of the drive
# ===========================================================================
#  Pressed ONCE on a computer that has never played this drive, and again
#  only when something has stopped working. It is the only way in that is
#  allowed to change anything about the computer, and the only way in that
#  rebuilds the two icons at the top of the drive.
#
#  THE SHAPE IS THE DESIGN: every question first, then all the work with
#  nobody watching. Somebody setting up at a friend's house answers two
#  things in the first ten seconds and can then walk away, instead of being
#  called back to a dialog three minutes in.
#
#  A COMPUTER IT ALREADY KNOWS KEEPS ITS PROFILE. Pressing this twice must
#  not make a second profile or throw away a tier that was chosen on purpose.
#  It re-does everything else and asks about the buttons again, because the
#  buttons are the part that breaks when the drive changes letter.
#
#  It ends on the Play page, because the next thing anybody wants is to play.
# ---------------------------------------------------------------------------
# Move the drive to R: (Windows asks for permission), then put right the one
# thing on this computer that remembers the old letter by itself: Steam's
# library list. Returns the DriveLetter.ps1 result plus NewRoot and Extra
# (words to add to the message, or '').
function Invoke-DriveLetterMove {
    $oldRoot = $Root
    $dlr = Invoke-DriveLetterElevated -Root $Root
    Log ('drive letter: ' + $dlr.Message)
    $newRoot = ''
    $extra = ''
    if ($dlr.Changed) {
        $newRoot = $dlr.To + ':' + $oldRoot.Substring(2)
        if ($script:steamOk) {
            try {
                $oldLib = Join-Path (Split-Path $oldRoot -Parent) 'SteamLibrary'
                $newLib = Join-Path (Split-Path $newRoot -Parent) 'SteamLibrary'
                $s = Move-SteamLibraryLetter -Root $newRoot -OldLibraryPath $oldLib -NewLibraryPath $newLib
                Log ('steam after letter change: ' + $s.Message)
                if ($s.Changed -or -not $s.Ok) { $extra = "`n`n" + $s.Message }
            }
            catch { Log ('steam after letter change failed - ' + $_.Exception.Message) }
        }
    }
    $dlr | Add-Member -NotePropertyName NewRoot -NotePropertyValue $newRoot -Force
    $dlr | Add-Member -NotePropertyName Extra -NotePropertyValue $extra -Force
    return $dlr
}

# Open this wizard again from a new drive letter. The copy running now was
# opened from the old letter, so every path it holds is stale.
function Restart-WizardFrom([string]$NewRoot, [string]$Mode = '') {
    try {
        $vbs = Join-Path $NewRoot '_ClaudeWorkspace\wizard\Launch-Wizard.vbs'
        $ws  = Join-Path $env:SystemRoot 'System32\wscript.exe'
        $a = '//nologo "' + $vbs + '"'
        if ($Mode -ne '') { $a += ' ' + $Mode }
        Start-Process -FilePath $ws -ArgumentList $a -ErrorAction Stop | Out-Null
        Log ('restarted the wizard from ' + $NewRoot + ' ' + $Mode)
    }
    catch { Log ('could not restart the wizard - ' + $_.Exception.Message) }
}

function Start-SetupFlow {
    Log '--- Setup flow ---'

    # --- 1. RetroBat must be closed: most of the work below writes settings
    if (Test-RetroBatRunning) {
        $pick = Show-Choice $WizardName "RetroBat is open.`n`nSetting up rewrites settings files that RetroBat rewrites again when it closes, so it has to be shut first." @('Close RetroBat', 'Stop')
        if ($pick -ne 'Close RetroBat') { Log 'setup: stopped, RetroBat left open'; Close-Splash; return }
        Close-RetroBat
    }

    # --- 1a. a fresh install: Quick or Advanced, and the profile ----------
    #  (2026-10-10) The installer leaves _ClaudeWorkspace\first-run.txt. Quick
    #  asks only what nobody else can answer (who you are, where the buttons
    #  go) and picks good defaults for the rest; Advanced asks about each part.
    #  Everything asked here can be changed later on a tab, and the last
    #  message says which.
    $firstRun = Test-Path -LiteralPath (Join-Path $Ws 'first-run.txt')
    $setupMode = 'normal'
    if ($firstRun) {
        Close-Splash
        $pick = Show-Choice $WizardName ("Welcome! The wizard is installed.`n`nQuick setup asks two things and picks good defaults for everything else. Advanced setup asks about each part. Either way, it can all be changed later in the wizard.") @('Quick setup', 'Advanced setup')
        $setupMode = $(if ($pick -eq 'Advanced setup') { 'advanced' } else { 'quick' })
        Log ("setup: first run, {0}" -f $setupMode)
        if ($script:socialOk) {
            $sp = $null
            try { $sp = Read-SocialProfile $Ws } catch { }
            if ($null -eq $sp) {
                $p2 = Show-Choice $WizardName ("Make a profile?`n`nWith a profile you can add friends, see who is online and what they are playing, and they can see you. As a guest, nothing about you is ever sent.`n`nAlready have one from another drive? Pick 'I have one' and log in on the Profile tab.") @('Make my profile', 'I have one', 'Play as a guest')
                if ($p2 -eq 'Make my profile') { Invoke-SocialCreate }
                if ($null -eq (Read-SocialProfile $Ws)) { Invoke-SocialGuest }
            }
        }
        if ($setupMode -eq 'advanced' -and $script:featuresOk) {
            try {
                $fv = Show-FeaturePicker
                if ($null -ne $fv) { [void](Set-Features -Root $Root -Values $fv); Log 'setup: features chosen' }
            } catch { Log "setup: feature picker failed: $_" }
        }
        # Video levelling needs ffmpeg, which is too big to ship through
        # GitHub. Without it the switch goes OFF, so setup does not fail a
        # step and the Health tab does not warn forever. Putting ffmpeg.exe in
        # _ClaudeWorkspace\tools and switching it back on is all it takes.
        if ($script:featuresOk -and -not (Test-Path -LiteralPath (Join-Path $Ws 'tools\ffmpeg.exe')) -and $null -eq (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
            try { [void](Set-Features -Root $Root -Values @{ videovolume = $false }); $script:noFfmpeg = $true; Log 'setup: no ffmpeg, video levelling switched off' } catch { }
        }
    }

    # --- 1b. the drive letter, FIRST of everything --------------------------
    #  Moved here from the very end on 2026-09-25. At the end, every icon and
    #  shortcut the setup had just made pointed at the OLD letter and broke
    #  the moment the letter moved, and so did Steam's link to the drive, so
    #  the first R: on a computer meant running setup twice and reconnecting
    #  Steam by hand. Now the letter moves before anything is built, Steam's
    #  library list is corrected on the spot, and setup restarts itself from
    #  the new letter and carries on - one run, nothing to redo.
    #
    #  Only asked when it can actually be done. If R: is already ours, or
    #  something else holds it, there is nothing to offer. Not being an
    #  administrator does not count: Windows is asked for permission.
    if ($script:driveLetterOk -and $setupMode -ne 'quick') {
        try {
            $dl = Get-DriveLetterStatus -Root $Root
            Log ('drive letter: ' + $dl.Line)
            if ($dl.State -eq 'canchange' -or $dl.State -eq 'needsadmin') {
                $pick = Show-Choice $WizardName ("Give this drive the letter R: on this computer?`n`nNothing on the drive needs it - everything here works out where it is by itself, and will keep working as {0}:. R: is a safety net for the odd setting inside an emulator that insists on a letter, and it is free because nothing else ever uses R:.`n`nWindows remembers this for this computer only, and will ask for permission first - say Yes. If Steam is open it closes for a moment so its link to the drive can be updated. Setup then restarts itself from R: and carries on." -f $dl.Current) @('Yes, use R:', 'Leave it')
                if ($pick -eq 'Yes, use R:') {
                    $dlr = Invoke-DriveLetterMove
                    if ($dlr.Changed) {
                        [void](Show-Choice $WizardName ($dlr.Message + $dlr.Extra + "`n`nSetup will now start again from " + $dlr.To + ": and carry on from here.") @('OK'))
                        Restart-WizardFrom -NewRoot $dlr.NewRoot -Mode '-Setup'
                        Close-Splash
                        return
                    }
                    [void](Show-Choice $WizardName $dlr.Message @('OK'))
                }
            }
        }
        catch { Log "setup: drive letter step failed: $_" }
    }

    # --- 2. the tier, but only for a computer with no profile yet ----------
    $mp = $null
    try { $mp = Resolve-MachineProfile -Root $Root -NoWrite } catch { Log "setup: profile resolve failed: $_" }

    $wantTier = ''
    if ($null -ne $mp -and $mp.Ok -and $mp.Created -and $setupMode -eq 'quick') {
        $wantTier = [string]$mp.Tier
        Log ("setup: quick, using the suggested {0} tier" -f $wantTier)
    }
    elseif ($null -ne $mp -and $mp.Ok -and $mp.Created) {
        $pick = Show-Choice $WizardName ("New computer: {0}`nGraphics card: {1}`n`nSuggesting the {2} tier. Low favours smoothness, High favours picture quality." -f $mp.Machine, $mp.Gpu, ([string]$mp.Tier).ToUpper()) @("Use $($mp.Tier)", 'Pick another')
        $wantTier = [string]$mp.Tier
        if ($pick -eq 'Pick another') {
            $t2 = Show-Choice $WizardName 'Pick a tier for this computer. The Machine tab changes it later.' @('Low', 'Medium', 'High')
            if ($t2 -ne '') { $wantTier = $t2.ToLower() }
        }
    }
    elseif ($null -ne $mp -and $mp.Ok) {
        Log ("setup: {0} already has a profile ({1} tier), leaving it alone" -f $mp.Machine, $mp.Tier)
    }

    # --- 3. the buttons on this computer, asked every time -----------------
    $places = @()
    $doPlaces = $false
    if ($script:localSetupOk) {
        $current = @()
        try { $current = @(Get-LocalSetupPlaces -WizardName $WizardName) } catch { }
        $ans = Show-PlaceToggles $WizardName "Where should this computer's buttons go?`n`nPlay, this wizard and a Controllers button, with icons copied onto the computer so they stay put when the drive is unplugged. Nothing is written to the drive." $current
        if ($ans.Ok) { $places = @($ans.Places); $doPlaces = $true }
    }

    # --- 3c. the controller shortcut, asked only while it is off ------------
    #  Per computer, like the buttons above. The answer is applied with the
    #  rest of the work below.
    $padChoice = ''
    if ($script:padShortcutOk -and $setupMode -ne 'quick') {
        $padOn = $false
        try { $padOn = Test-PadShortcutOn } catch { }
        if ($padOn) {
            # Already on here: no question (2026-09-25 - asking again read as if
            # the first Yes had not stuck). Installing again just refreshes this
            # computer's copy of the helper, which is harmless and keeps it current.
            $padChoice = 'on'
            Log 'setup: controller shortcut already on - not asking'
        }
        else {
            $msg = "Open this wizard with a controller?`n`nWith this on, pressing SELECT + START together on any controller opens this wizard full screen, and you can use it with the controller. It only works when no game and no RetroBat menu is open, so it never gets in the way of quitting a game.`n`nIt only affects this computer, and it can be switched on or off any time on the Features tab."
            $pick = Show-Choice $WizardName $msg @('Yes, turn it on', 'No thanks')
            if ($pick -eq 'Yes, turn it on') { $padChoice = 'on' }
        }
    }
    # --- 3d. first run: the theme and netplay defaults ------------------------
    #  RetroBat is closed here, which is the only time es_settings.cfg can be
    #  written. ckau-book is the look this drive's extras are built for; it is
    #  only switched to when RetroBat's own theme downloader has put it there
    #  (about 2 GB, far better fetched by RetroBat than by this). Netplay gets
    #  private rooms and the profile name.
    $themeMissing = $false
    if ($firstRun -and $script:netplayOk) {
        try {
            if (Test-Path -LiteralPath (Join-Path $Root 'emulationstation\.emulationstation\themes\ckau-book\theme.xml')) {
                if (Set-EsStringSetting $Root 'ThemeSet' 'ckau-book') { Log 'setup: theme set to ckau-book' }
            }
            else { $themeMissing = $true }
            $np = @{ Private = $true }
            $nn = Get-NetplayWantedName
            if ($nn -ne '') { $np.Nickname = $nn }
            [void](Set-NetplaySettings $Root $np)
        } catch { Log "setup: theme/netplay defaults failed: $_" }
    }

    # --- 4. all the work, one progress window ------------------------------
    #  Built as ONE list first so "Step 4 of 9" counts what will actually run
    #  rather than what might.
    $work = New-Object System.Collections.ArrayList
    [void]$work.Add(@('script', 'Restore-ProtectedFiles.ps1', 'putting protected files back'))
    [void]$work.Add(@('script', 'Fix-Portability.ps1',        'fixing drive letters'))
    [void]$work.Add(@('script', 'Apply-Settings.ps1',         'applying your settings'))
    [void]$work.Add(@('script', 'Restore-CkauBookTheme.ps1',  'restoring theme collections'))
    [void]$work.Add(@('script', 'Decompress-3DS.ps1',         'checking for new 3DS games'))
    if (-not $script:noFfmpeg) { [void]$work.Add(@('script', 'Fix-VideoVolume.ps1', 'levelling video volume')) }
    if ($wantTier -ne '' -and $null -ne $mp -and $wantTier -ne [string]$mp.Tier) {
        [void]$work.Add(@('tier', $wantTier, "setting this computer to $($wantTier.ToUpper())"))
    }
    if ($doPlaces)          { [void]$work.Add(@('places', '', "putting this computer's buttons in place")) }
    if ($padChoice -ne '')  { [void]$work.Add(@('pad', $padChoice, 'setting up the controller shortcut')) }
    if ($script:shortcutsOk) {
        [void]$work.Add(@('roots',  '', 'rebuilding the icons at the top of the drive'))
    }
    [void]$work.Add(@('health', '', 'checking the drive over'))

    $status = Invoke-SetupWork $work $places
    Log 'setup: work finished'

    # --- 5. record RetroBat's version, or the next Play decides an update
    #        happened and runs all six steps over again -----------------------
    try {
        $cur = Get-RetroBatVersion
        if ($cur -ne '') {
            [System.IO.File]::WriteAllLines($StatePath, @("lastretrobatversion = $cur"), (New-Object System.Text.UTF8Encoding($false)))
        }
    }
    catch { Log "setup: could not record the RetroBat version - $_" }

    if ($firstRun) { Complete-FirstRun $themeMissing }

    Show-MainWindow $status 'play'
}

# The end of a fresh install: say where everything lives, set the first-run
# note aside, and tidy the installer's files out of the RetroBat folder.
function Complete-FirstRun([bool]$ThemeMissing) {
    $msg = "All set!`n`nYou can change any of this later:`n  Profile tab - your name, picture and friends`n  Games tab - add games, and the free library`n  Netplay tab - playing online`n  Machine tab - picture quality on this computer`n  Features tab - the extras this wizard adds`n  Help tab - updates, bug reports, suggestions"
    if ($script:noFfmpeg) {
        $msg += "`n`nVideo volume levelling is off for now: it needs a free tool called ffmpeg, which is not on this drive yet."
    }
    if ($ThemeMissing) {
        $msg += "`n`nOne optional thing: for the full look, open RetroBat, press START, go to UPDATES & DOWNLOADS > THEMES and install ckau-book (a big download, about 2 GB). Then press Play in the wizard and it switches to it for you. Everything else already works without it."
    }
    [void](Show-Choice $WizardName $msg @('Let''s play'))
    try {
        $safe = Join-Path $Ws '_SAFE TO DELETE\installer'
        if (-not (Test-Path -LiteralPath $safe)) { [void](New-Item -ItemType Directory -Path $safe -Force) }
        Move-Item -LiteralPath (Join-Path $Ws 'first-run.txt') -Destination (Join-Path $safe ('first-run-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')) -Force
        foreach ($f in @('INSTALL THE WIZARD.bat', 'Install-Wizard.ps1', 'token.txt')) {
            $p = Join-Path $Root $f
            if (Test-Path -LiteralPath $p) { Move-Item -LiteralPath $p -Destination (Join-Path $safe $f) -Force }
        }
        Log 'setup: first run finished, installer files set aside'
    } catch { Log "setup: could not tidy the installer files: $_" }
}

# Advanced setup: every switch on the Features tab, as checkboxes. Returns the
# chosen values, or $null on Cancel.
function Show-FeaturePicker {
    $cat = Get-FeatureCatalogue
    $cur = @{}
    try { $cur = Get-Features $Root } catch { }
    $w = New-Object System.Windows.Window
    $w.Title = $WizardName; $w.Width = 600; $w.Height = 560
    $w.WindowStartupLocation = 'CenterScreen'; $w.Background = (New-Brush $ColBg); $w.Topmost = $true
    $dp = New-Object System.Windows.Controls.DockPanel; $dp.Margin = '20'
    $hd = New-Text 'The extras this wizard adds. All of them are on unless you untick them. The Features tab changes them later.' $ColText 14
    $hd.TextWrapping = 'Wrap'; $hd.Margin = '0,0,0,10'
    [System.Windows.Controls.DockPanel]::SetDock($hd, 'Top'); [void]$dp.Children.Add($hd)
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.HorizontalAlignment = 'Right'; $row.Margin = '0,12,0,0'
    [System.Windows.Controls.DockPanel]::SetDock($row, 'Bottom')
    $sv = New-Object System.Windows.Controls.ScrollViewer; $sv.VerticalScrollBarVisibility = 'Auto'
    $list = New-Object System.Windows.Controls.StackPanel
    $script:fpBoxes = @{}
    foreach ($k in $cat.Keys) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = [string]$cat[$k].title; $cb.FontSize = 14; $cb.Foreground = (New-Brush $ColText); $cb.Margin = '0,8,0,0'
        $on = $true
        if ($null -ne $cur -and $cur.Contains($k)) { $on = [bool]$cur[$k] }
        $cb.IsChecked = $on
        [void]$list.Children.Add($cb)
        $d = New-Text ([string]$cat[$k].desc) $ColDim 12; $d.Margin = '22,0,0,0'; $d.TextWrapping = 'Wrap'
        [void]$list.Children.Add($d)
        $script:fpBoxes[$k] = $cb
    }
    $sv.Content = $list
    $script:fpWin = $w; $script:fpOk = $false
    foreach ($pair in @(@('Skip', $false), @('Use these', $true))) {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $pair[0]; $b.Tag = $pair[1]; $b.Padding = '14,6'; $b.FontSize = 14; $b.Margin = '8,0,0,0'
        $b.Add_Click({ param($s2, $e2) $script:fpOk = [bool]$s2.Tag; $script:fpWin.Close() })
        [void]$row.Children.Add($b)
    }
    [void]$dp.Children.Add($row); [void]$dp.Children.Add($sv)
    $w.Content = $dp
    [void]$w.ShowDialog()
    if (-not $script:fpOk) { return $null }
    $vals = @{}
    foreach ($k in $script:fpBoxes.Keys) { $vals[$k] = [bool]$script:fpBoxes[$k].IsChecked }
    return $vals
}


# Runs the list Start-SetupFlow built, behind one progress window that paints
# itself BEFORE the first step. Returns the health status, or $null.
function Invoke-SetupWork($Work, [string[]]$Places) {
    Close-Splash

    $w = New-Object System.Windows.Window
    $w.Title = $WizardName; $w.Width = 520; $w.Height = 160
    $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'NoResize'
    $w.Background = (New-Brush $ColBg); $w.Topmost = $true
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '22'
    $head = New-Text 'Setting this computer up...' $ColText 15 $true
    $line = New-Text 'Starting...' $ColDim 14
    $line.Margin = '0,10,0,0'; $line.TextWrapping = 'Wrap'
    [void]$sp.Children.Add($head); [void]$sp.Children.Add($line)
    $w.Content = $sp
    $w.Show()
    # Paint it before the first step, not after the last one.
    $w.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Render)

    $status = $null
    $n = 0
    $total = @($Work).Count
    foreach ($item in @($Work)) {
        $n++
        $line.Text = ("Step {0} of {1}: {2}..." -f $n, $total, $item[2])
        $w.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Render)

        switch ([string]$item[0]) {
            'script' { [void](Invoke-Step ([string]$item[1]) ([string]$item[2])) }
            'tier'   {
                try {
                    $mp2 = Resolve-MachineProfile -Root $Root -NoWrite
                    if ($mp2 -and $mp2.ProfileFile -and (Test-Path -LiteralPath $mp2.ProfileFile)) {
                        Set-ProfileTier $mp2.ProfileFile ([string]$item[1])
                        [void](Invoke-Step 'Apply-Settings.ps1' 'applying the chosen tier')
                    }
                }
                catch { Log "setup: could not set the tier - $_" }
            }
            'places' {
                try {
                    if (@($Places).Count -eq 0) { [void](Remove-LocalSetup -Logger { param($m) Log $m }) }
                    else { [void](Install-LocalSetup -Root $Root -WizardName $WizardName -Places $Places -Logger { param($m) Log $m }) }
                }
                catch { Log "setup: buttons on this computer - $_" }
            }
            'pad' {
                try {
                    if ([string]$item[1] -eq 'on') { [void](Install-PadShortcut -Root $Root -Logger { param($m) Log $m }) }
                    elseif (Test-PadShortcutOn)    { [void](Remove-PadShortcut -Logger { param($m) Log $m }) }
                }
                catch { Log "setup: controller shortcut - $_" }
            }
            'roots' {
                try {
                    [void](Update-RootFiles     -Root $Root -Logger { param($m) Log $m })
                    [void](Update-RootShortcuts -Root $Root -WizardName $WizardName -Logger { param($m) Log $m })
                }
                catch { Log "setup: drive-root icons - $_" }
            }
            'health' { $status = Invoke-Health }
        }
    }

    try { $w.Close() } catch { }
    return $status
}



# ===========================================================================
#  DRIVING THIS WINDOW WITH A CONTROLLER                        (2026-09-23)
# ---------------------------------------------------------------------------
#  Any controller, through scripts\PadInput.ps1 (RetroBat's own SDL2).
#
#     LB / RB          previous / next tab (wraps round)
#     D-pad or stick   move between buttons, boxes and lists
#     A                press whatever is highlighted. On the Play tab the
#                      Play button is highlighted to start with.
#     B                back: closes a dropdown or a question box, otherwise
#                      goes back to the Play tab
#     right stick      scrolls the page
#     SELECT + START   closes the wizard
#
#  START ON ITS OWN DOES NOTHING, on purpose. One button that shuts the
#  wizard and launches RetroBat is too easy to hit by accident; getting to
#  Play and pressing A is two deliberate moves.
#
#  MOVING picks the nearest thing in that direction on screen (see
#  RBPadUi.Spatial), so the highlight can always cross from one list to the
#  one beside it and never gets stuck on the tab headers. On the Saves tab,
#  A on a game jumps to its saves on the right; B goes back to the game.
#
#  THE HINT BAR at the bottom lists the above. It only appears when the
#  wizard was opened with SELECT + START, or when a controller is actually
#  being used, and fades away after six seconds without a button press.
#
#  A glowing box shows what is highlighted. Clicking the mouse hides it, so
#  a mouse user never sees it at all.
#
#  ONLY WHEN THE WIZARD IS IN FRONT. Pressing buttons while another program
#  is in front does nothing here.
#
#  IT CAN NEVER BE THE PROBLEM. It loads after the window is already on
#  screen, every step is wrapped, and if the controller library will not
#  start the window simply works with the mouse, exactly as before.
# ---------------------------------------------------------------------------
$script:padTimer      = $null
$script:padUiOk       = $false
$script:padPrev       = 0
$script:padLastInput  = [DateTime]::MinValue
$script:padHeldDir    = ''
$script:padRepeatAt   = [DateTime]::MinValue
$script:padHintsShown = $false
$script:padFading     = $false
$script:padClickTarget = $null

# The glowing box, and a few things PowerShell cannot do comfortably itself:
# which of our windows is in front, the first thing on a page that can be
# highlighted, and pressing a button exactly the way a mouse click does.
function Initialize-PadUi {
    if (([System.Management.Automation.PSTypeName]'RBPadUi').Type) { return $true }
    try {
        Add-Type -AssemblyName System.Xaml
        $refs = @(
            [System.Windows.Window].Assembly.Location,
            [System.Windows.UIElement].Assembly.Location,
            [System.Windows.DependencyObject].Assembly.Location,
            [System.Xaml.XamlReader].Assembly.Location
        )
        Add-Type -ReferencedAssemblies $refs -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
using System.Windows.Interop;
using System.Windows.Media;

public class RBPadRing : Adorner
{
    public RBPadRing(UIElement e) : base(e) { IsHitTestVisible = false; }
    protected override void OnRender(DrawingContext dc)
    {
        Rect r = new Rect(AdornedElement.RenderSize);
        Rect outer = r; outer.Inflate(5, 5);
        Rect inner = r; inner.Inflate(2, 2);
        dc.DrawRectangle(null, new Pen(new SolidColorBrush(Color.FromArgb(110, 111, 195, 255)), 6), outer);
        dc.DrawRectangle(null, new Pen(new SolidColorBrush(Color.FromRgb(191, 234, 255)), 3), inner);
    }
}

public static class RBPadUi
{
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();

    static RBPadRing ring;
    static UIElement ringOn;

    public static Window ActiveWindow()
    {
        IntPtr h = GetForegroundWindow();
        if (h == IntPtr.Zero) return null;
        HwndSource s = HwndSource.FromHwnd(h);
        if (s == null) return null;
        return s.RootVisual as Window;
    }

    public static void ShowRing(UIElement e)
    {
        HideRing();
        if (e == null || e is Window) return;
        AdornerLayer l = AdornerLayer.GetAdornerLayer(e);
        if (l == null) return;
        ring = new RBPadRing(e);
        ringOn = e;
        l.Add(ring);
        FrameworkElement fe = e as FrameworkElement;
        if (fe != null) fe.BringIntoView();
    }

    public static void HideRing()
    {
        if (ring != null && ringOn != null)
        {
            AdornerLayer l = AdornerLayer.GetAdornerLayer(ringOn);
            if (l != null) l.Remove(ring);
        }
        ring = null;
        ringOn = null;
    }

    static bool Usable(DependencyObject d)
    {
        Control c = d as Control;
        if (c == null) return false;
        if (!c.Focusable || !c.IsEnabled || !c.IsVisible) return false;
        if (c is ScrollViewer || c is TabItem || c is TabControl || c is Label || c is Window || c is ToolTip) return false;
        return true;
    }

    public static UIElement FirstFocusable(DependencyObject root)
    {
        if (root == null) return null;
        Queue<DependencyObject> q = new Queue<DependencyObject>();
        q.Enqueue(root);
        while (q.Count > 0)
        {
            DependencyObject d = q.Dequeue();
            if (d != root && Usable(d)) return d as UIElement;
            if (!(d is Visual)) continue;
            int n = VisualTreeHelper.GetChildrenCount(d);
            for (int i = 0; i < n; i++) q.Enqueue(VisualTreeHelper.GetChild(d, i));
        }
        return null;
    }

    public static ScrollViewer FindScroll(DependencyObject start, DependencyObject root)
    {
        DependencyObject d = start;
        while (d != null)
        {
            ScrollViewer sv = d as ScrollViewer;
            if (sv != null && sv.ScrollableHeight > 0) return sv;
            d = (d is Visual) ? VisualTreeHelper.GetParent(d) : null;
        }
        if (root == null) return null;
        Queue<DependencyObject> q = new Queue<DependencyObject>();
        q.Enqueue(root);
        while (q.Count > 0)
        {
            DependencyObject x = q.Dequeue();
            ScrollViewer sv = x as ScrollViewer;
            if (sv != null && sv.ScrollableHeight > 0 && sv.IsVisible) return sv;
            if (!(x is Visual)) continue;
            int n = VisualTreeHelper.GetChildrenCount(x);
            for (int i = 0; i < n; i++) q.Enqueue(VisualTreeHelper.GetChild(x, i));
        }
        return null;
    }

    // SPATIAL NAVIGATION (2026-09-23). WPF's own arrow-key movement gets
    // stuck: a list will not let the highlight out sideways, and the tab
    // headers swallowed it. This picks the nearest thing that can be pressed
    // in the direction asked, by where things actually are on screen. The
    // tab headers are never candidates - the bumpers change tabs.
    public static UIElement Spatial(UIElement from, DependencyObject root, string dir)
    {
        Visual rv = root as Visual;
        if (rv == null || from == null) return null;
        Rect f;
        if (!TryBounds(from, rv, out f)) return null;
        double fcx = f.X + f.Width / 2, fcy = f.Y + f.Height / 2;
        UIElement best = null;
        double bestScore = double.MaxValue;
        foreach (UIElement c in AllUsable(root))
        {
            if (c == from) continue;
            if (c.IsAncestorOf(from) || from.IsAncestorOf(c)) continue;
            Rect r;
            if (!TryBounds(c, rv, out r)) continue;
            double cx = r.X + r.Width / 2, cy = r.Y + r.Height / 2;
            double primary, gap, off;
            if (dir == "Down")
            {
                if (cy <= fcy + 1 || r.Top < f.Top + 2) continue;
                primary = Math.Max(0, r.Top - f.Bottom);
                gap = Math.Max(0, Math.Max(r.Left - f.Right, f.Left - r.Right));
                off = Math.Abs(cx - fcx);
            }
            else if (dir == "Up")
            {
                if (cy >= fcy - 1 || r.Bottom > f.Bottom - 2) continue;
                primary = Math.Max(0, f.Top - r.Bottom);
                gap = Math.Max(0, Math.Max(r.Left - f.Right, f.Left - r.Right));
                off = Math.Abs(cx - fcx);
            }
            else if (dir == "Right")
            {
                if (cx <= fcx + 1 || r.Left < f.Left + 2) continue;
                primary = Math.Max(0, r.Left - f.Right);
                gap = Math.Max(0, Math.Max(r.Top - f.Bottom, f.Top - r.Bottom));
                off = Math.Abs(cy - fcy);
            }
            else if (dir == "Left")
            {
                if (cx >= fcx - 1 || r.Right > f.Right - 2) continue;
                primary = Math.Max(0, f.Left - r.Right);
                gap = Math.Max(0, Math.Max(r.Top - f.Bottom, f.Top - r.Bottom));
                off = Math.Abs(cy - fcy);
            }
            else continue;
            double score = primary + gap * 3 + off * 0.3;
            if (score < bestScore) { bestScore = score; best = c; }
        }
        return best;
    }

    static bool TryBounds(UIElement e, Visual root, out Rect r)
    {
        r = Rect.Empty;
        try
        {
            if (!e.IsVisible || !root.IsAncestorOf(e)) return false;
            r = e.TransformToAncestor(root).TransformBounds(new Rect(e.RenderSize));
            return true;
        }
        catch { return false; }
    }

    static List<UIElement> AllUsable(DependencyObject root)
    {
        List<UIElement> list = new List<UIElement>();
        Queue<DependencyObject> q = new Queue<DependencyObject>();
        q.Enqueue(root);
        while (q.Count > 0)
        {
            DependencyObject d = q.Dequeue();
            UIElement u = d as UIElement;
            if (u != null && !u.IsVisible) continue;
            if (d != root && Usable(d) && !(d is ListBox)) list.Add((UIElement)d);
            if (!(d is Visual)) continue;
            int n = VisualTreeHelper.GetChildrenCount(d);
            for (int i = 0; i < n; i++) q.Enqueue(VisualTreeHelper.GetChild(d, i));
        }
        return list;
    }

    public static bool Inside(DependencyObject child, DependencyObject ancestor)
    {
        Visual a = ancestor as Visual;
        Visual c = child as Visual;
        if (a == null || c == null) return false;
        return a == c || a.IsAncestorOf(c);
    }

    public static Panel FindTabPanel(DependencyObject root)
    {
        Queue<DependencyObject> q = new Queue<DependencyObject>();
        q.Enqueue(root);
        while (q.Count > 0)
        {
            DependencyObject d = q.Dequeue();
            if (d is TabPanel) return (Panel)d;
            if (!(d is Visual)) continue;
            int n = VisualTreeHelper.GetChildrenCount(d);
            for (int i = 0; i < n; i++) q.Enqueue(VisualTreeHelper.GetChild(d, i));
        }
        return null;
    }

    // Exactly what a mouse click does: ButtonBase.OnClick. It toggles a
    // CheckBox AND raises Click, which is what every handler here listens to.
    public static bool Click(object o)
    {
        ButtonBase b = o as ButtonBase;
        if (b == null) return false;
        MethodInfo m = typeof(ButtonBase).GetMethod("OnClick", BindingFlags.NonPublic | BindingFlags.Instance);
        if (m == null) return false;
        m.Invoke(b, null);
        return true;
    }
}
'@
        return $true
    }
    catch { Log ("pad: could not build the highlight box - {0}" -f $_.Exception.Message); return $false }
}

# Started from the window's Loaded handler, and deliberately a moment LATER
# (Background priority) so the window is already on screen while the
# controller parts are being put together.
function Start-PadNav {
    try {
        [void]$script:win.Dispatcher.BeginInvoke([action]{ Initialize-PadNav }, [System.Windows.Threading.DispatcherPriority]::Background)
    } catch { Log ("pad: " + $_.Exception.Message) }
}

function Initialize-PadNav {
    try {
        # The SELECT + START helper on this computer: refresh it if the drive
        # has a newer one, restart it if it has stopped. Does nothing at all
        # on a computer where it is switched off.
        if ($script:padShortcutOk) { Update-PadShortcut -Root $Root -Logger { param($m) Log $m } }

        $lib = Join-Path $ScriptsDir 'PadInput.ps1'
        if (-not (Test-Path -LiteralPath $lib)) { Log 'pad: PadInput.ps1 not found, mouse only'; return }
        . $lib

        $dll = Join-Path $Root 'emulationstation\SDL2.dll'
        if (-not (Test-Path -LiteralPath $dll) -and $script:padShortcutOk) { $dll = Join-Path (Get-PadFolder) 'SDL2.dll' }
        if (-not [RBPad]::Init($dll)) { Log ("pad: controller library would not start - " + [RBPad]::LastError); return }

        $script:padUiOk = Initialize-PadUi
        Initialize-PadGlyphs
        $script:win.Add_SizeChanged({ if ($script:padBumpersPlaced) { Update-PadBumpers } })

        $t = New-Object System.Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromMilliseconds(40)
        $t.Add_Tick({ try { Invoke-PadTick } catch { } })
        $t.Start()
        $script:padTimer = $t

        $script:win.Add_Closed({
            try { if ($null -ne $script:padTimer) { $script:padTimer.Stop(); $script:padTimer = $null } } catch { }
            try { [RBPad]::Quit() } catch { }
        })
        $script:win.Add_PreviewMouseDown({ try { if ($script:padUiOk) { [RBPadUi]::HideRing() } } catch { } })

        Log ("pad: controller control ready, {0} controller(s) connected" -f [RBPad]::Count)
        if ($script:padLaunch) {
            Show-PadHints
            Set-PadFocus (Get-PadDefault $script:win)
        }
    }
    catch { Log ("pad: " + $_.Exception.Message) }
}

# The button pictures in the hint bar and beside the tabs. They are drawn
# at 2 pixels per art pixel already, so they are shown at exactly one real
# screen pixel each (the same whole-number rule as every picture here), and
# they do NOT grow with the window - they sit next to text that does not.
function Initialize-PadGlyphs {
    try {
        $dpi = Get-DpiScale
        $k = [math]::Max(1, [math]::Round($dpi, [System.MidpointRounding]::AwayFromZero)) / $dpi
        $sc = New-Object System.Windows.Media.ScaleTransform($k, $k)
        $pairs = @(
            @('HintDpad', 'pad-dpad.png'), @('HintA', 'pad-a.png'), @('HintB', 'pad-b.png'),
            @('HintR', 'pad-rstick.png'), @('HintView', 'pad-view.png'), @('HintMenu', 'pad-menu.png'),
            @('BumperL', 'pad-lb.png'), @('BumperR', 'pad-rb.png')
        )
        foreach ($p in $pairs) {
            $img = $script:win.FindName($p[0])
            if ($null -eq $img) { continue }
            $bmp = Get-PixelBitmap (Join-Path $WizardDir $p[1])
            if ($null -eq $bmp) { continue }
            $img.Source = $bmp
            $img.LayoutTransform = $sc
        }
    }
    catch { Log ("pad: button pictures - " + $_.Exception.Message) }
}

# LB to the left of the first tab, RB to the right of the last one. The tab
# strip is nudged right once, the first time a controller is used, to make
# room, and stays there - the pictures fade with the hint bar but the tabs
# never jump back and forth.
$script:padBumpersPlaced = $false
function Update-PadBumpers {
    try {
        if (-not $script:padUiOk -or $null -eq $script:bumperL -or $null -eq $script:bumperR) { return }
        if ($null -eq $script:bumperL.Source) { return }
        $tp = [RBPadUi]::FindTabPanel($script:tabs)
        if ($null -eq $tp) { return }
        $bw = [double]$script:bumperL.Source.PixelWidth * ([math]::Max(1, [math]::Round((Get-DpiScale), [System.MidpointRounding]::AwayFromZero)) / (Get-DpiScale))
        $bh = [double]$script:bumperL.Source.PixelHeight * ([math]::Max(1, [math]::Round((Get-DpiScale), [System.MidpointRounding]::AwayFromZero)) / (Get-DpiScale))
        $tp.Margin = New-Object System.Windows.Thickness(($bw + 12), 0, 0, 0)
        $script:win.UpdateLayout()

        $n = $script:tabs.Items.Count
        $first = $script:tabs.ItemContainerGenerator.ContainerFromIndex(0)
        $last  = $script:tabs.ItemContainerGenerator.ContainerFromIndex($n - 1)
        if ($null -eq $first -or $null -eq $last) { return }
        $p1 = $first.TransformToAncestor($script:tabsHost).Transform((New-Object System.Windows.Point(0, 0)))
        $p2 = $last.TransformToAncestor($script:tabsHost).Transform((New-Object System.Windows.Point($last.ActualWidth, 0)))
        $y = $p1.Y + ($first.ActualHeight - $bh) / 2
        $script:bumperL.Margin = New-Object System.Windows.Thickness(($p1.X - $bw - 6), $y, 0, 0)
        $script:bumperR.Margin = New-Object System.Windows.Thickness(($p2.X + 6), $y, 0, 0)
        $script:padBumpersPlaced = $true
    }
    catch { Log ("pad: bumpers - " + $_.Exception.Message) }
}

function Show-PadHints {
    $h = $script:padHints
    if ($null -eq $h) { return }
    $script:padLastInput = [DateTime]::UtcNow
    if ($script:padHintsShown -and -not $script:padFading) { return }
    foreach ($e in @($h, $script:bumperL, $script:bumperR)) {
        if ($null -eq $e) { continue }
        $e.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
        $e.Opacity = 1
        $e.Visibility = 'Visible'
    }
    $script:padHintsShown = $true
    $script:padFading = $false
    if (-not $script:padBumpersPlaced) {
        [void]$script:win.Dispatcher.BeginInvoke([action]{ Update-PadBumpers }, [System.Windows.Threading.DispatcherPriority]::Loaded)
    }
}

function Hide-PadHints {
    $h = $script:padHints
    if ($null -eq $h) { return }
    $script:padFading = $true
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation(1.0, 0.0, (New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(900))))
    $a.Add_Completed({
        if ($script:padFading) {
            $script:padHints.Visibility = 'Collapsed'
            $script:padHintsShown = $false
            $script:padFading = $false
        }
    })
    $h.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $a)
    foreach ($e in @($script:bumperL, $script:bumperR)) {
        if ($null -eq $e) { continue }
        $e.BeginAnimation([System.Windows.UIElement]::OpacityProperty,
            (New-Object System.Windows.Media.Animation.DoubleAnimation(1.0, 0.0, (New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(900))))))
    }
}

# What gets highlighted first: the Play button on the Play tab, otherwise
# the first thing on the page that can be pressed. In a question box, its
# first button.
function Get-PadDefault($w) {
    if ($null -eq $w) { return $null }
    if ($w -eq $script:win) {
        if ($script:tabs.SelectedIndex -eq 0) { return $script:playButton }
        if ($script:padUiOk) { return [RBPadUi]::FirstFocusable($script:tabs.SelectedContent) }
        return $null
    }
    if ($script:padUiOk) { return [RBPadUi]::FirstFocusable($w) }
    return $null
}

function Set-PadFocus($el) {
    if ($null -eq $el) { return }
    try {
        [void]$el.Focus()
        [void][System.Windows.Input.Keyboard]::Focus($el)
        if ($script:padUiOk) { [RBPadUi]::ShowRing($el) }
    } catch { }
}

function Get-PadFocused {
    $el = [System.Windows.Input.Keyboard]::FocusedElement
    if ($el -is [System.Windows.UIElement] -and -not ($el -is [System.Windows.Window])) { return $el }
    return $null
}

# Where the highlight can travel: the open tab's page (never the tab headers
# - the bumpers change tabs), or the whole of a question box.
function Get-PadRoot($w) {
    if ($w -eq $script:win) { return $script:tabs.SelectedContent }
    return $w
}

function Move-PadFocus($w, [string]$dir) {
    $cur = Get-PadFocused
    if ($null -eq $cur -or [System.Windows.Window]::GetWindow($cur) -ne $w -or $cur -is [System.Windows.Controls.TabItem]) {
        Set-PadFocus (Get-PadDefault $w); return
    }

    # Inside an open dropdown, or up and down a list, WPF's own movement is
    # the right one: it scrolls the list and fetches rows that are not drawn
    # yet. Only when it cannot go any further does the highlight leave.
    $inList = ($cur -is [System.Windows.Controls.ListBoxItem]) -or ($cur -is [System.Windows.Controls.ComboBoxItem])
    if ($inList -and ($dir -eq 'Up' -or $dir -eq 'Down')) {
        $req = New-Object System.Windows.Input.TraversalRequest([System.Windows.Input.FocusNavigationDirection]::$dir)
        [void]$cur.MoveFocus($req)
        $now = Get-PadFocused
        if ($null -ne $now -and $now -ne $cur) {
            if ($script:padUiOk) { [RBPadUi]::ShowRing($now) }
            return
        }
        if ($cur -is [System.Windows.Controls.ComboBoxItem]) { return }
    }

    $next = $null
    if ($script:padUiOk) { $next = [RBPadUi]::Spatial($cur, (Get-PadRoot $w), $dir) }
    if ($null -ne $next) { Set-PadFocus $next; return }

    # Nothing further that way. Leave the highlight where it is.
    if ($script:padUiOk) { [RBPadUi]::ShowRing($cur) }
}

function Step-PadTab([int]$d) {
    $n = $script:tabs.Items.Count
    if ($n -lt 1) { return }
    $script:tabs.SelectedIndex = (($script:tabs.SelectedIndex + $d) % $n + $n) % $n
    [void]$script:win.Dispatcher.BeginInvoke([action]{ Set-PadFocus (Get-PadDefault $script:win) }, [System.Windows.Threading.DispatcherPriority]::Loaded)
}

# A press that opens a question box must not happen INSIDE the timer tick,
# so buttons are pressed a moment later, on their own.
function Invoke-PadClickLater($el) {
    $script:padClickTarget = $el
    [void]$script:win.Dispatcher.BeginInvoke([action]{
        try {
            $t = $script:padClickTarget
            $script:padClickTarget = $null
            if ($null -eq $t) { return }
            if ($script:padUiOk) { [void][RBPadUi]::Click($t) }
            else { $t.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
        } catch { Log ("pad: press failed - " + $_.Exception.Message) }
    }, [System.Windows.Threading.DispatcherPriority]::Input)
}

function Invoke-PadSelect($w) {
    $el = Get-PadFocused
    if ($null -eq $el -or [System.Windows.Window]::GetWindow($el) -ne $w) {
        if ($w -eq $script:win -and $script:tabs.SelectedIndex -eq 0) { Set-PadFocus $script:playButton; Invoke-PadClickLater $script:playButton; return }
        Set-PadFocus (Get-PadDefault $w); return
    }
    if ($el -is [System.Windows.Controls.Primitives.ButtonBase]) { Invoke-PadClickLater $el; return }
    if ($el -is [System.Windows.Controls.ComboBoxItem]) {
        $cb = [System.Windows.Controls.ItemsControl]::ItemsControlFromItemContainer($el)
        if ($null -ne $cb) {
            $cb.SelectedItem = $cb.ItemContainerGenerator.ItemFromContainer($el)
            $cb.IsDropDownOpen = $false
            Set-PadFocus $cb
        }
        return
    }
    if ($el -is [System.Windows.Controls.ComboBox]) {
        $el.IsDropDownOpen = -not $el.IsDropDownOpen
        if ($el.IsDropDownOpen) {
            # Put the highlight on the choice that is already picked, so
            # up / down walks the list and A picks one.
            $script:padOpenCombo = $el
            [void]$script:win.Dispatcher.BeginInvoke([action]{
                $cb = $script:padOpenCombo
                if ($null -eq $cb) { return }
                $i = [math]::Max(0, $cb.SelectedIndex)
                $it = $cb.ItemContainerGenerator.ContainerFromIndex($i)
                if ($null -ne $it) { [void]$it.Focus() }
            }, [System.Windows.Threading.DispatcherPriority]::Loaded)
        }
        return
    }
    if ($el -is [System.Windows.Controls.ListBoxItem]) {
        $el.IsSelected = $true
        # The Saves tab: picking a game fills the right-hand side, so the
        # highlight goes straight there instead of making you travel the
        # whole list to reach it. B brings it back to the game.
        $lb = [System.Windows.Controls.ItemsControl]::ItemsControlFromItemContainer($el)
        if ($null -ne $lb -and $lb -eq $script:saveListBox -and $null -ne $script:saveDetail) {
            [void]$script:win.Dispatcher.BeginInvoke([action]{
                $first = $null
                if ($script:padUiOk) { $first = [RBPadUi]::FirstFocusable($script:saveDetail) }
                if ($null -ne $first) { Set-PadFocus $first }
            }, [System.Windows.Threading.DispatcherPriority]::Loaded)
        }
        return
    }
    if ($el -is [System.Windows.Controls.TabItem])     { $el.IsSelected = $true; return }
    if ($el -is [System.Windows.Controls.Expander])    { $el.IsExpanded = -not $el.IsExpanded; return }
    try {
        $peer = [System.Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($el)
        if ($null -ne $peer) {
            $inv = $peer.GetPattern([System.Windows.Automation.Peers.PatternInterface]::Invoke)
            if ($null -ne $inv) { $inv.Invoke() }
        }
    } catch { }
}

function Invoke-PadBack($w) {
    $el = Get-PadFocused
    if ($el -is [System.Windows.Controls.ComboBoxItem]) {
        $cb = [System.Windows.Controls.ItemsControl]::ItemsControlFromItemContainer($el)
        if ($null -ne $cb) { $cb.IsDropDownOpen = $false; Set-PadFocus $cb }
        return
    }
    if ($el -is [System.Windows.Controls.ComboBox] -and $el.IsDropDownOpen) { $el.IsDropDownOpen = $false; return }
    if ($w -ne $script:win) { try { $w.Close() } catch { }; return }
    if ($script:padUiOk -and $null -ne $el -and $null -ne $script:saveDetail -and [RBPadUi]::Inside($el, $script:saveDetail)) {
        $i = $script:saveListBox.SelectedIndex
        if ($i -ge 0) {
            $c = $script:saveListBox.ItemContainerGenerator.ContainerFromIndex($i)
            if ($null -ne $c) { Set-PadFocus $c; return }
        }
        Set-PadFocus $script:saveListBox
        return
    }
    if ($script:tabs.SelectedIndex -ne 0) { Step-PadTab (0 - $script:tabs.SelectedIndex) }
    else { Set-PadFocus $script:playButton }
}

function Invoke-PadScroll($w, [bool]$down) {
    if (-not $script:padUiOk) { return }
    $root = $w
    if ($w -eq $script:win) { $root = $script:tabs.SelectedContent }
    $sv = [RBPadUi]::FindScroll((Get-PadFocused), $root)
    if ($null -eq $sv) { return }
    if ($down) { $sv.LineDown(); $sv.LineDown() } else { $sv.LineUp(); $sv.LineUp() }
}

function Invoke-PadTick {
    $s = [RBPad]::Poll()
    $prev = $script:padPrev
    $script:padPrev = $s
    $new = $s -band (-bnot $prev)
    $now = [DateTime]::UtcNow

    if ($script:padHintsShown -and -not $script:padFading -and ($now - $script:padLastInput).TotalSeconds -gt 6) { Hide-PadHints }
    if ($s -eq 0) { $script:padHeldDir = ''; return }

    # Only when one of OUR windows is in front.
    $active = $script:win
    if ($script:padUiOk) { $active = [RBPadUi]::ActiveWindow() }
    if ($null -eq $active) { return }

    Show-PadHints
    $B = $script:PadBit

    # SELECT + START closes the wizard. It leaves a note for the background
    # helper, which would otherwise see the same two buttons still held and
    # open the wizard straight back up again.
    if ((($s -band $B.Back) -ne 0) -and (($s -band $B.Start) -ne 0) -and (($new -band ($B.Back -bor $B.Start)) -ne 0)) {
        try {
            if ($script:padShortcutOk) { [System.IO.File]::WriteAllText((Join-Path (Get-PadFolder) 'wizard-closed.txt'), 'closed') }
        } catch { }
        Log 'pad: closed with SELECT + START'
        if ($active -ne $script:win) { try { $active.Close() } catch { } }
        $script:win.Close()
        return
    }

    if ($active -eq $script:win) {
        if (($new -band $B.LB) -ne 0) { Step-PadTab -1; return }
        if (($new -band $B.RB) -ne 0) { Step-PadTab 1;  return }
    }

    $dir = ''
    if     ($s -band ($B.Up    -bor $B.StickUp))    { $dir = 'Up' }
    elseif ($s -band ($B.Down  -bor $B.StickDown))  { $dir = 'Down' }
    elseif ($s -band ($B.Left  -bor $B.StickLeft))  { $dir = 'Left' }
    elseif ($s -band ($B.Right -bor $B.StickRight)) { $dir = 'Right' }
    if ($dir -ne '') {
        if ($script:padHeldDir -ne $dir) {
            $script:padHeldDir = $dir
            $script:padRepeatAt = $now.AddMilliseconds(420)
            Move-PadFocus $active $dir
        }
        elseif ($now -ge $script:padRepeatAt) {
            $script:padRepeatAt = $now.AddMilliseconds(110)
            Move-PadFocus $active $dir
        }
    }
    else { $script:padHeldDir = '' }

    if (($new -band $B.A) -ne 0) { Invoke-PadSelect $active; return }
    if (($new -band $B.B) -ne 0) { Invoke-PadBack $active; return }
    if ($s -band ($B.RStickUp -bor $B.RStickDown)) { Invoke-PadScroll $active (($s -band $B.RStickDown) -ne 0) }
}


# --- the main window --------------------------------------------------------
function Show-MainWindow($status, [string]$startTab = 'play') {

    if ($null -eq $status) { $status = Invoke-Health }

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="900" Height="640" WindowStartupLocation="CenterScreen"
        Background="#FF1B1B22">
  <Window.Resources>
    <!-- The 8-bit Play button. The dark edge and the green fill are each
         three overlapping rectangles, and the overlap is what puts the
         stepped notch on every corner. No image and no rounded corners, so
         there is nothing to go stale and nothing extra to ship. The three
         fill rectangles are named because a trigger can only retarget one
         element at a time. -->
    <Style x:Key="PixelButton" TargetType="Button">
      <Setter Property="Background" Value="#FF2FA84F"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid Background="Transparent">
              <Border Background="#FF0E0E16" Margin="8,0,8,0"/>
              <Border Background="#FF0E0E16" Margin="0,8,0,8"/>
              <Border Background="#FF0E0E16" Margin="4,4,4,4"/>
              <Border x:Name="Fill1" Background="{TemplateBinding Background}" Margin="12,4,12,4"/>
              <Border x:Name="Fill2" Background="{TemplateBinding Background}" Margin="4,12,4,12"/>
              <Border x:Name="Fill3" Background="{TemplateBinding Background}" Margin="8,8,8,8"/>
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Fill1" Property="Background" Value="#FF3CC162"/>
                <Setter TargetName="Fill2" Property="Background" Value="#FF3CC162"/>
                <Setter TargetName="Fill3" Property="Background" Value="#FF3CC162"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Fill1" Property="Background" Value="#FF23803C"/>
                <Setter TargetName="Fill2" Property="Background" Value="#FF23803C"/>
                <Setter TargetName="Fill3" Property="Background" Value="#FF23803C"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- A button that is just a picture. The stock Button paints a pale
         chrome background of its own that ignores Background, which is why
         this needs a template rather than a Setter: with no box at all until
         the mouse is over it, the Play page keeps one thing to look at, and
         the box that appears is the grey it used to sit in permanently. -->
    <Style x:Key="IconButton" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Box" Background="Transparent" Padding="7">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Box" Property="Background" Value="#FF33333E"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Box" Property="Background" Value="#FF464655"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <DockPanel>
    <Border DockPanel.Dock="Bottom" Background="#FF14141A" Padding="12,7">
      <TextBlock x:Name="FooterText" Foreground="#FF9AA0AA" FontSize="13"/>
    </Border>
    <!-- The controller hints (2026-09-23). Shown only when the wizard was
         opened with SELECT + START or a controller is being used, and faded
         away after six seconds without a button press. See Show-PadHints. -->
    <Border x:Name="PadHints" DockPanel.Dock="Bottom" Background="#FF22223A" Padding="14,7" Visibility="Collapsed">
      <!-- Each hint is the controller button's own picture (wizard\pad-*.png,
           cut from Steven's button sheet) and one word. A missing picture
           just leaves the word. -->
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
        <StackPanel.Resources>
          <Style TargetType="Image">
            <Setter Property="Stretch" Value="None"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="RenderOptions.BitmapScalingMode" Value="NearestNeighbor"/>
          </Style>
          <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#FFCFE6FF"/>
            <Setter Property="FontSize" Value="15"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Margin" Value="7,0,26,0"/>
          </Style>
        </StackPanel.Resources>
        <Image x:Name="HintDpad"/><TextBlock Text="Move"/>
        <Image x:Name="HintA"/><TextBlock Text="Select"/>
        <Image x:Name="HintB"/><TextBlock Text="Back"/>
        <Image x:Name="HintR"/><TextBlock Text="Scroll"/>
        <Image x:Name="HintView"/><TextBlock Text="+" Margin="4,0,4,0"/><Image x:Name="HintMenu"/><TextBlock Text="Close" Margin="7,0,0,0"/>
      </StackPanel>
    </Border>
    <!-- The TabControl sits in a Grid so the LB / RB pictures can sit either
         side of the tab strip when a controller is in use (2026-09-23).
         Update-PadBumpers places them; until then they are hidden. -->
    <!-- The update bar (2026-10-10). Hidden until a newer version turns up on
         GitHub. Nothing downloads and nothing installs until Update now is
         pressed. -->
    <Border x:Name="UpdateBar" DockPanel.Dock="Top" Background="#FF22223A" Padding="14,8" Visibility="Collapsed">
      <DockPanel>
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
          <Button x:Name="UpdateNotesBtn" Content="What's new" Padding="12,4" FontSize="13" Margin="0,0,8,0"/>
          <Button x:Name="UpdateLaterBtn" Content="Later" Padding="12,4" FontSize="13" Margin="0,0,8,0"/>
          <Button x:Name="UpdateNowBtn" Content="Update now" Padding="12,4" FontSize="13" FontWeight="Bold"/>
        </StackPanel>
        <TextBlock x:Name="UpdateBarText" Foreground="#FFCFE6FF" FontSize="14" VerticalAlignment="Center" TextWrapping="Wrap" Margin="0,0,12,0"/>
      </DockPanel>
    </Border>
    <Grid x:Name="TabsHost">
    <TabControl x:Name="Tabs" Background="#FF1B1B22" BorderThickness="0" Margin="6">
      <!-- The tab's own pixel icon. Stretch="None" keeps it at its real
           size, which is the only way pixel art stays square, and a
           missing wizard\tab-*.png just leaves the words on their own. -->
      <TabItem>
        <TabItem.Header>
          <StackPanel Orientation="Horizontal">
            <Image x:Name="IconPlay" Stretch="None" VerticalAlignment="Center" Margin="2,0,7,0"
                   RenderOptions.BitmapScalingMode="NearestNeighbor"/>
            <TextBlock Text="Play" VerticalAlignment="Center" Margin="0,0,4,0"/>
          </StackPanel>
        </TabItem.Header>
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <!-- Top row: the name on the left, the mage in the top RIGHT
               corner (moved there 2026-09-23). A Grid rather than a
               StackPanel so the two can sit at opposite ends. -->
          <Grid Grid.Row="0">
            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Left" Margin="26,16,0,0">
              <!-- The pixel wordmark, shown only when wizard\wordmark.png is
                   there. It is optional ON PURPOSE: a future owner who renames
                   the drive deletes that one file and the plain text name
                   below comes back, so the name still lives in exactly one
                   place. Stretch="None" keeps it at its own size, which is the
                   only way pixel art stays square. -->
              <Image x:Name="BrandWordmark" Stretch="None" HorizontalAlignment="Left"
                     Visibility="Collapsed"
                     RenderOptions.BitmapScalingMode="NearestNeighbor"/>
              <TextBlock x:Name="BrandName" Foreground="#FFE8E8EC" FontSize="23" FontWeight="Bold"/>
              <TextBlock x:Name="BrandSub" Foreground="#FF9AA0AA" FontSize="13" Margin="0,5,0,0"/>
            </StackPanel>
            <!-- Stretch="None" and NO Width or Height: the picture is
                 already its own exact size (150 x 150 since 2026-09-23, with
                 room round the mage for his aura and sparks), and asking for
                 that size in WPF's
                 units made Windows resample it on a scaled display. Its size
                 is set by the LayoutTransform in Update-PlayScale, which
                 chooses a number that comes out whole in real screen pixels. -->
            <Image x:Name="LogoImage" Stretch="None" VerticalAlignment="Top" HorizontalAlignment="Right" Margin="0,6,20,0"
                   RenderOptions.BitmapScalingMode="NearestNeighbor"/>
          </Grid>
          <Button x:Name="PlayButton" Grid.Row="1" Style="{StaticResource PixelButton}"
                  Content="PLAY" Width="300" Height="106" FontSize="34" FontWeight="Bold"
                  HorizontalAlignment="Center" VerticalAlignment="Center"/>
          <!-- The controller button, bottom left of the front page. It is the
               SAME picture as the Controllers icon this drive writes onto a
               computer, so the thing you click here and the thing you click on
               the desktop are recognisably one thing. It opens Windows' own
               game controller list, reads nothing and changes nothing - "is
               that pad even plugged in" is the first question at a party, and
               it belongs on the page you are already looking at.
               A missing wizard\controllers.png just leaves the box empty. -->
          <Button x:Name="PadButton" Grid.Row="2" Style="{StaticResource IconButton}"
                  HorizontalAlignment="Left" VerticalAlignment="Bottom"
                  Margin="26,0,0,12" ToolTip="Check my controllers">
            <Image x:Name="PadImage" Stretch="None"
                   RenderOptions.BitmapScalingMode="NearestNeighbor"/>
          </Button>
          <StackPanel x:Name="LightsPanel" Grid.Row="2" Margin="110,0,110,20"/>
        </Grid>
      </TabItem>
      <!-- The tab's own pixel icon. Stretch="None" keeps it at its real
           size, which is the only way pixel art stays square, and a
           missing wizard\tab-*.png just leaves the words on their own. -->
      <!-- The Profile tab (2026-10-10): who is using this drive, their
           friends, and what everybody is playing. Built in code by
           Render-Social, like the Machine tab. -->
      <TabItem>
        <TabItem.Header>
          <StackPanel Orientation="Horizontal">
            <Image x:Name="IconProfile" Stretch="None" VerticalAlignment="Center" Margin="2,0,7,0"
                   RenderOptions.BitmapScalingMode="NearestNeighbor"/>
            <TextBlock Text="Profile" VerticalAlignment="Center" Margin="0,0,4,0"/>
          </StackPanel>
        </TabItem.Header>
        <DockPanel Margin="10">
          <Grid>
            <Image x:Name="ArtProfile" Stretch="None"
                   HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,10,4" IsHitTestVisible="False"
                   RenderOptions.BitmapScalingMode="NearestNeighbor"/>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel x:Name="SocialPanel" Margin="6,0,14,10"/>
            </ScrollViewer>
          </Grid>
        </DockPanel>
      </TabItem>
      <!-- The Games tab (2026-10-10): add a game from this computer, and
           the online library. Built in code by Render-Games. -->
      <TabItem>
        <TabItem.Header>
          <StackPanel Orientation="Horizontal">
            <Image x:Name="IconGames" Stretch="None" VerticalAlignment="Center" Margin="2,0,7,0"
                   RenderOptions.BitmapScalingMode="NearestNeighbor"/>
            <TextBlock Text="Games" VerticalAlignment="Center" Margin="0,0,4,0"/>
          </StackPanel>
        </TabItem.Header>
        <DockPanel Margin="10">
          <Grid>
            <Image x:Name="ArtGames" Stretch="None"
                   HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,10,4" IsHitTestVisible="False"
                   RenderOptions.BitmapScalingMode="NearestNeighbor"/>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel x:Name="GamesPanel" Margin="6,0,14,10"/>
            </ScrollViewer>
          </Grid>
        </DockPanel>
      </TabItem>
      <!-- The Netplay tab (2026-10-10): playing online, one card per
           console. Built in code by Render-Netplay. -->
      <TabItem>
        <TabItem.Header>
          <StackPanel Orientation="Horizontal">
            <Image x:Name="IconNetplay" Stretch="None" VerticalAlignment="Center" Margin="2,0,7,0"
                   RenderOptions.BitmapScalingMode="NearestNeighbor"/>
            <TextBlock Text="Netplay" VerticalAlignment="Center" Margin="0,0,4,0"/>
          </StackPanel>
        </TabItem.Header>
        <DockPanel Margin="10">
          <Grid>
            <Image x:Name="ArtNetplay" Stretch="None"
                   HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,10,4" IsHitTestVisible="False"
                   RenderOptions.BitmapScalingMode="NearestNeighbor"/>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel x:Name="NetplayPanel" Margin="6,0,14,10"/>
            </ScrollViewer>
          </Grid>
        </DockPanel>
      </TabItem>
      <TabItem>
        <TabItem.Header>
          <StackPanel Orientation="Horizontal">
            <Image x:Name="IconHealth" Stretch="None" VerticalAlignment="Center" Margin="2,0,7,0"
                   RenderOptions.BitmapScalingMode="NearestNeighbor"/>
            <TextBlock Text="Health" VerticalAlignment="Center" Margin="0,0,4,0"/>
          </StackPanel>
        </TabItem.Header>
        <DockPanel Margin="10">
          <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="6,4,0,10">
            <Button x:Name="RefreshButton" Content="Re-run the checks" Padding="14,6" FontSize="14"/>
            <!-- The "Check my controllers" button used to be here. It moved to
                 the bottom left of the Play tab on 2026-09-18, as the
                 controller picture, because that is the page that is already
                 open when somebody picks up a pad. -->
            <TextBlock x:Name="RefreshNote" Foreground="#FF9AA0AA" FontSize="13" Margin="14,8,0,0"/>
          </StackPanel>
          <!-- The corner picture and the page share ONE cell since
               2026-09-23. It used to be docked along the bottom, which
               took the whole width of the page and cut every list off
               at its top edge. Now it sits BEHIND the page in the
               bottom-right corner, so lists run all the way down and
               anything with a background simply covers it. -->
          <Grid>
            <Image x:Name="ArtHealth" Stretch="None"
                   HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,10,4" IsHitTestVisible="False"
                   RenderOptions.BitmapScalingMode="NearestNeighbor"/>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel x:Name="HealthPanel" Margin="6,0"/>
            </ScrollViewer>
          </Grid>
        </DockPanel>
      </TabItem>
      <!-- The tab's own pixel icon. Stretch="None" keeps it at its real
           size, which is the only way pixel art stays square, and a
           missing wizard\tab-*.png just leaves the words on their own. -->
      <TabItem>
        <TabItem.Header>
          <StackPanel Orientation="Horizontal">
            <Image x:Name="IconProfiles" Stretch="None" VerticalAlignment="Center" Margin="2,0,7,0"
                   RenderOptions.BitmapScalingMode="NearestNeighbor"/>
            <TextBlock Text="Machine" VerticalAlignment="Center" Margin="0,0,4,0"/>
          </StackPanel>
        </TabItem.Header>
        <DockPanel Margin="10">
          <Border x:Name="ProfileBar" DockPanel.Dock="Bottom" Background="#FF2A2A34"
                  Padding="12,9" Visibility="Collapsed">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
              <TextBlock x:Name="ProfileBarText" Foreground="#FFE5B83B" FontSize="13" Margin="0,7,16,0"/>
              <Button x:Name="ProfileUndo" Content="Undo" Padding="14,6" FontSize="14" Margin="0,0,8,0"/>
              <Button x:Name="ProfileApply" Content="Apply changes" Padding="14,6" FontSize="14"/>
            </StackPanel>
          </Border>
          <!-- The corner picture and the page share ONE cell since
               2026-09-23. It used to be docked along the bottom, which
               took the whole width of the page and cut every list off
               at its top edge. Now it sits BEHIND the page in the
               bottom-right corner, so lists run all the way down and
               anything with a background simply covers it. -->
          <Grid>
            <Image x:Name="ArtProfiles" Stretch="None"
                   HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,10,4" IsHitTestVisible="False"
                   RenderOptions.BitmapScalingMode="NearestNeighbor"/>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel x:Name="ProfilePanel" Margin="6,0,14,10"/>
            </ScrollViewer>
          </Grid>
        </DockPanel>
      </TabItem>
      <!-- The tab's own pixel icon. Stretch="None" keeps it at its real
           size, which is the only way pixel art stays square, and a
           missing wizard\tab-*.png just leaves the words on their own. -->
      <TabItem>
        <TabItem.Header>
          <StackPanel Orientation="Horizontal">
            <Image x:Name="IconSaves" Stretch="None" VerticalAlignment="Center" Margin="2,0,7,0"
                   RenderOptions.BitmapScalingMode="NearestNeighbor"/>
            <TextBlock Text="Saves" VerticalAlignment="Center" Margin="0,0,4,0"/>
          </StackPanel>
        </TabItem.Header>
        <DockPanel Margin="10">
          <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="6,4,0,10">
            <Button x:Name="SaveBackupBtn" Content="Back up saves now" Padding="14,6" FontSize="14"/>
            <TextBlock Text="Console:" Foreground="#FF9AA0AA" FontSize="13" Margin="16,9,6,0"/>
            <ComboBox x:Name="SaveConsole" Width="120" FontSize="13" Height="26"/>
            <CheckBox x:Name="SaveShowAll" Content="Show arcade and system files too" Foreground="#FFE8E8EC"
                      FontSize="13" Margin="16,9,0,0"/>
            <TextBlock x:Name="SaveNote" Foreground="#FF9AA0AA" FontSize="13" Margin="16,8,0,0"/>
          </StackPanel>
          <!-- The corner picture and the page share ONE cell since
               2026-09-23. It used to be docked along the bottom, which
               took the whole width of the page and cut every list off
               at its top edge. Now it sits BEHIND the page in the
               bottom-right corner, so lists run all the way down and
               anything with a background simply covers it. -->
          <Grid>
            <Image x:Name="ArtSaves" Stretch="None"
                   HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,10,4" IsHitTestVisible="False"
                   RenderOptions.BitmapScalingMode="NearestNeighbor"/>
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="330"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <ListBox x:Name="SaveList" Grid.Column="0" Margin="6,0,10,0" FontSize="13"
                       Background="#FF23232C" Foreground="#FFE8E8EC" BorderThickness="0"
                       ScrollViewer.HorizontalScrollBarVisibility="Disabled"/>
              <ScrollViewer Grid.Column="1" VerticalScrollBarVisibility="Auto">
                <StackPanel x:Name="SaveDetail" Margin="4,0,14,10"/>
              </ScrollViewer>
            </Grid>
          </Grid>
        </DockPanel>
      </TabItem>
      <!-- The tab's own pixel icon. Stretch="None" keeps it at its real
           size, which is the only way pixel art stays square, and a
           missing wizard\tab-*.png just leaves the words on their own. -->
      <TabItem>
        <TabItem.Header>
          <StackPanel Orientation="Horizontal">
            <Image x:Name="IconFeatures" Stretch="None" VerticalAlignment="Center" Margin="2,0,7,0"
                   RenderOptions.BitmapScalingMode="NearestNeighbor"/>
            <TextBlock Text="Features" VerticalAlignment="Center" Margin="0,0,4,0"/>
          </StackPanel>
        </TabItem.Header>
        <DockPanel Margin="10">
          <Border x:Name="FeatureBar" DockPanel.Dock="Bottom" Background="#FF2A2A34"
                  Padding="12,9" Visibility="Collapsed">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
              <TextBlock x:Name="FeatureBarText" Foreground="#FFE5B83B" FontSize="13" Margin="0,7,16,0"/>
              <Button x:Name="FeatureUndo" Content="Undo" Padding="14,6" FontSize="14" Margin="0,0,8,0"/>
              <Button x:Name="FeatureApply" Content="Apply changes" Padding="14,6" FontSize="14"/>
            </StackPanel>
          </Border>
          <!-- The corner picture and the page share ONE cell since
               2026-09-23. It used to be docked along the bottom, which
               took the whole width of the page and cut every list off
               at its top edge. Now it sits BEHIND the page in the
               bottom-right corner, so lists run all the way down and
               anything with a background simply covers it. -->
          <Grid>
            <Image x:Name="ArtFeatures" Stretch="None"
                   HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,10,4" IsHitTestVisible="False"
                   RenderOptions.BitmapScalingMode="NearestNeighbor"/>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel x:Name="FeaturePanel" Margin="6,0,14,10"/>
            </ScrollViewer>
          </Grid>
        </DockPanel>
      </TabItem>
      <!-- The tab's own pixel icon. Stretch="None" keeps it at its real
           size, which is the only way pixel art stays square, and a
           missing wizard\tab-*.png just leaves the words on their own. -->
      <TabItem>
        <TabItem.Header>
          <StackPanel Orientation="Horizontal">
            <Image x:Name="IconHelp" Stretch="None" VerticalAlignment="Center" Margin="2,0,7,0"
                   RenderOptions.BitmapScalingMode="NearestNeighbor"/>
            <TextBlock Text="Help" VerticalAlignment="Center" Margin="0,0,4,0"/>
          </StackPanel>
        </TabItem.Header>
        <DockPanel>
          <!-- The corner picture and the page share ONE cell since
               2026-09-23. It used to be docked along the bottom, which
               took the whole width of the page and cut every list off
               at its top edge. Now it sits BEHIND the page in the
               bottom-right corner, so lists run all the way down and
               anything with a background simply covers it. -->
          <Grid>
            <Image x:Name="ArtHelp" Stretch="None"
                   HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,10,4" IsHitTestVisible="False"
                   RenderOptions.BitmapScalingMode="NearestNeighbor"/>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel x:Name="HelpPanel" Margin="20,12,20,16"/>
            </ScrollViewer>
          </Grid>
        </DockPanel>
      </TabItem>
    </TabControl>
    <Image x:Name="BumperL" Stretch="None" HorizontalAlignment="Left" VerticalAlignment="Top"
           Visibility="Collapsed" IsHitTestVisible="False" RenderOptions.BitmapScalingMode="NearestNeighbor"/>
    <Image x:Name="BumperR" Stretch="None" HorizontalAlignment="Left" VerticalAlignment="Top"
           Visibility="Collapsed" IsHitTestVisible="False" RenderOptions.BitmapScalingMode="NearestNeighbor"/>
    </Grid>
  </DockPanel>
</Window>
'@

    # Everything the event handlers touch lives at SCRIPT scope. Event
    # scriptblocks in Windows PowerShell reliably see script scope and
    # top-level functions, but NOT a function's local variables.
    $script:win         = [Windows.Markup.XamlReader]::Parse($xaml)
    # A mistake inside a button's code used to take the whole window down
    # (2026-10-10, the first profile). Now it is caught here: logged, a report
    # offered, and the person chooses whether to keep going or close.
    $script:win.Dispatcher.Add_UnhandledException({
        param($s2, $e2)
        $e2.Handled = $true
        try { Invoke-SoftCrash $e2.Exception } catch { }
    })
    $script:win.Title   = "$WizardName  -  v$WizardVersion"
    $script:tabs        = $script:win.FindName('Tabs')
    $script:playButton  = $script:win.FindName('PlayButton')
    $script:lightsPanel = $script:win.FindName('LightsPanel')
    $script:healthPanel = $script:win.FindName('HealthPanel')
    $script:refreshBtn  = $script:win.FindName('RefreshButton')
    $script:refreshNote = $script:win.FindName('RefreshNote')
    $script:footer      = $script:win.FindName('FooterText')
    $script:padHints    = $script:win.FindName('PadHints')
    $script:tabsHost    = $script:win.FindName('TabsHost')
    $script:bumperL     = $script:win.FindName('BumperL')
    $script:bumperR     = $script:win.FindName('BumperR')
    $script:profilePanel   = $script:win.FindName('ProfilePanel')
    $script:profileBar     = $script:win.FindName('ProfileBar')
    $script:profileBarText = $script:win.FindName('ProfileBarText')
    $script:profileApplyBtn = $script:win.FindName('ProfileApply')
    $script:profileUndoBtn  = $script:win.FindName('ProfileUndo')
    $script:saveListBox   = $script:win.FindName('SaveList')
    $script:saveDetail    = $script:win.FindName('SaveDetail')
    $script:saveNote      = $script:win.FindName('SaveNote')
    $script:saveBackupBtn = $script:win.FindName('SaveBackupBtn')
    $script:saveShowAllBx = $script:win.FindName('SaveShowAll')
    $script:saveConsoleBx = $script:win.FindName('SaveConsole')
    $script:featurePanel   = $script:win.FindName('FeaturePanel')
    $script:featureBar     = $script:win.FindName('FeatureBar')
    $script:featureBarText = $script:win.FindName('FeatureBarText')
    $script:featureApplyBtn = $script:win.FindName('FeatureApply')
    $script:featureUndoBtn  = $script:win.FindName('FeatureUndo')
    $script:logoImage   = $script:win.FindName('LogoImage')
    $script:brandName   = $script:win.FindName('BrandName')
    $script:brandSub    = $script:win.FindName('BrandSub')
    $script:brandWordmark = $script:win.FindName('BrandWordmark')
    $script:padButton   = $script:win.FindName('PadButton')
    $script:padImage    = $script:win.FindName('PadImage')
    $script:helpPanel   = $script:win.FindName('HelpPanel')
    $script:socialPanel = $script:win.FindName('SocialPanel')
    $script:netplayPanel = $script:win.FindName('NetplayPanel')
    $script:gamesPanel = $script:win.FindName('GamesPanel')
    $script:updateBar      = $script:win.FindName('UpdateBar')
    $script:updateBarText  = $script:win.FindName('UpdateBarText')
    $script:updateNowBtn   = $script:win.FindName('UpdateNowBtn')
    $script:updateLaterBtn = $script:win.FindName('UpdateLaterBtn')
    $script:updateNotesBtn = $script:win.FindName('UpdateNotesBtn')
    # The little picture on each tab, in tab order. Looked up by name one at a
    # time like everything else here, so the static test can check every one of
    # them against the XAML.
    $script:tabIconImages = @(
        $script:win.FindName('IconPlay'),
        $script:win.FindName('IconProfile'),
        $script:win.FindName('IconGames'),
        $script:win.FindName('IconNetplay'),
        $script:win.FindName('IconHealth'),
        $script:win.FindName('IconProfiles'),
        $script:win.FindName('IconSaves'),
        $script:win.FindName('IconFeatures'),
        $script:win.FindName('IconHelp')
    )
    # The big picture in the corner of each page, in the SAME tab order. Play
    # has none, so its slot is a deliberate $null.
    $script:pageArtImages = @(
        $null,
        $script:win.FindName('ArtProfile'),
        $script:win.FindName('ArtGames'),
        $script:win.FindName('ArtNetplay'),
        $script:win.FindName('ArtHealth'),
        $script:win.FindName('ArtProfiles'),
        $script:win.FindName('ArtSaves'),
        $script:win.FindName('ArtFeatures'),
        $script:win.FindName('ArtHelp')
    )
    $script:uiStatus    = $status

    Initialize-Brand
    Initialize-PadIcon
    Initialize-TabIcons
    Initialize-PageArt
    Render-Status
    Initialize-Profiles
    Render-Profiles
    Initialize-Saves
    Render-SaveConsoleList
    Render-SaveGames
    Initialize-FeatureTab
    Render-Features
    Render-Help
    Render-Social
    Render-Netplay
    Render-Games
    Sync-AdminTab

    $script:profileApplyBtn.Add_Click({ Invoke-ProfileApply })
    $script:profileUndoBtn.Add_Click({ Initialize-Profiles; Render-Profiles })

    $script:featureApplyBtn.Add_Click({ Invoke-FeatureApply })
    $script:featureUndoBtn.Add_Click({ Initialize-FeatureTab; Render-Features; Update-FeatureDirty })

    # SelectedIndex is the only link between the list on screen and the real
    # objects in $script:saveList. They are built in the same order by
    # Render-SaveGames, and nothing else is allowed to reorder either one.
    $script:saveListBox.Add_SelectionChanged({
        $i = $script:saveListBox.SelectedIndex
        if ($i -ge 0 -and $i -lt $script:saveList.Count) { $script:saveSelected = $script:saveList[$i] }
        else { $script:saveSelected = $null }
        Render-SaveDetail
    })
    $script:saveShowAllBx.Add_Click({
        $script:saveShowAll = [bool]$script:saveShowAllBx.IsChecked
        $script:saveSelected = $null
        Render-SaveConsoleList
        Render-SaveGames
    })
    $script:saveConsoleBx.Add_SelectionChanged({
        # Filling the dropdown fires this too, which would reset the list
        # mid-refresh. The flag is why Render-SaveConsoleList sets it.
        if ($script:saveConsoleLoading) { return }
        $script:saveConsole = [string]$script:saveConsoleBx.SelectedItem
        $script:saveSelected = $null
        Render-SaveGames
    })
    $script:saveBackupBtn.Add_Click({ Invoke-SaveBackupNow })

    $script:updateNowBtn.Add_Click({ Invoke-WizardUpdate 'Update' })
    $script:updateLaterBtn.Add_Click({ $script:updateBar.Visibility = 'Collapsed' })
    $script:updateNotesBtn.Add_Click({ Show-UpdateNotes })

    $script:playButton.Add_Click({
        $script:win.Close()
        Start-PlayFlow
    })
    # Windows' own controller panel. control.exe is called by its full path
    # for the same reason PowerShell always is here: whatever launched the
    # wizard may not have handed down a normal PATH.
    if ($null -ne $script:padButton) {
        $script:padButton.Add_Click({
            try {
                Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\control.exe') -ArgumentList 'joy.cpl'
            }
            catch { Log ("controllers: could not open joy.cpl - {0}" -f $_.Exception.Message) }
        })
    }

    $script:refreshBtn.Add_Click({
        $script:refreshNote.Text = 'Checking...'
        $script:win.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Render)
        $script:uiStatus = Invoke-Health
        Render-Status
        $script:refreshNote.Text = ''
    })

    # ('profiles' still means Machine, for old callers.)
    $want = $(if ($startTab -eq 'profiles') { 'machine' } else { $startTab })
    $ti = Get-TabIndex $want
    if ($ti -gt 0) { $script:tabs.SelectedIndex = $ti }

    # --- come up in front, and appear on the taskbar ----------------------
    #  The wizard is started by wscript.exe through a hidden console, and
    #  Windows will not hand the foreground to a process that never had it.
    #  The result was a window that opened BEHIND everything and had no
    #  taskbar button until it was clicked once - which is hard to click when
    #  you cannot see it.
    #
    #  Topmost while it is coming up is the part Windows always honours. It is
    #  dropped again in the same breath, in the Loaded handler, so the wizard
    #  does not then sit rudely on top of everything else for as long as it is
    #  open. Activate() asks for the keyboard as well.
    # Opened with SELECT + START: full screen, no title bar, covering the
    # taskbar - it is being used from the sofa. SELECT + START closes it.
    if ($script:padLaunch) {
        $script:win.WindowStyle = 'None'
        $script:win.WindowState = 'Maximized'
        Log 'opened from a controller: full screen'
    }
    $script:win.ShowInTaskbar = $true
    $script:win.Topmost       = $true
    $script:win.Add_Loaded({
        try {
            $script:win.Activate()
            $script:win.Topmost = $false
        } catch { }
        Update-PlayScale
        Start-PadNav
        # A few bytes from GitHub, in the background, after the window is up,
        # so a slow or missing connection can never hold the window back.
        Start-UpdatePeek
        Start-SocialSession
    })
    $script:win.Add_SizeChanged({ Update-PlayScale })

    Close-Splash
    [void]$script:win.ShowDialog()
}

# which script fixes which light (each also exists as a Maintenance button)
$script:fixMap = @{
    savebackups    = @('Backup-RetroBatSaves.ps1',  'Back up saves now')
    protectedfiles = @('Restore-ProtectedFiles.ps1','Restore protected files')
    settings       = @('Apply-Settings.ps1',        'Re-apply my settings')
    driveletters   = @('Fix-Portability.ps1',       'Fix drive letters')
    videovolume    = @('Fix-VideoVolume.ps1',       'Fix video volume')
}
# fixes that must not run while RetroBat is open (they change settings)
$script:needsClosed = @('protectedfiles','settings','driveletters','videovolume')

# Fills the Play-tab lights, the Health-tab cards and the footer from
# $script:uiStatus. Top-level so event handlers can call it.
# ===========================================================================
#  The pixel art  (the wordmark's fire, the tab icons, the status lights)
# ---------------------------------------------------------------------------
#  Three things in this window are pixel pictures now, and they all follow the
#  SAME two rules.
#
#  1. A MISSING PICTURE IS NEVER AN ERROR. No wordmark.png means the plain
#     text name comes back. No tab-*.png means that tab keeps just its word.
#     No lights.png means the plain coloured dots that were here before. It is
#     the rule the feature switches follow: the worst a missing file can do is
#     nothing. That is what lets a future owner redraw any of these in any
#     pixel editor, or throw one away, without opening this file.
#
#  2. NOTHING STORES A FRAME COUNT. An animation strip is one frame per row,
#     stacked downwards, so the number of frames is the strip's height divided
#     by one frame's height. There is no second file to keep in step, and it
#     self-checks: if that division does not come out whole, the animation is
#     skipped and the still picture stays. Which is the right answer, not a bug.
#
#  ONE TIMER RUNS THEM ALL. Every moving picture is a row in
#  $script:spriteLoops, and a single DispatcherTimer steps all of them
#  together. A fourth costs nothing and they cannot drift apart.
# ===========================================================================

$script:spriteLoops = New-Object System.Collections.ArrayList
$script:spriteTimer = $null
# The clock every moving picture runs on. 50 ms = 20 frames a second. It was
# 125 ms (8 a second) until 2026-09-23, which is why the old pictures looked
# like they were ticking rather than moving. A loop that wants to go slower
# says so with -EveryMs and simply skips ticks.
$script:SpriteTickMs = 50

# Loads a picture and lets go of the file again. CacheOption OnLoad is not
# optional: without it WPF holds the file open, and a drive with an open file
# on it will not eject.
function Get-PixelBitmap([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $b = New-Object System.Windows.Media.Imaging.BitmapImage
        $b.BeginInit()
        $b.UriSource = New-Object System.Uri($Path)
        $b.CacheOption = 'OnLoad'
        $b.EndInit()
        return $b
    }
    catch {
        Log ("art: could not load {0} - {1}" -f (Split-Path -Leaf $Path), $_.Exception.Message)
        return $null
    }
}

# Cuts one frame out of a picture. Frozen, so the timer is not handing the UI
# thread a live object to re-evaluate eight times a second.
function Get-SpriteFrame($Sheet, [int]$X, [int]$Y, [int]$W, [int]$H) {
    $rect = New-Object System.Windows.Int32Rect($X, $Y, $W, $H)
    $c = New-Object System.Windows.Media.Imaging.CroppedBitmap($Sheet, $rect)
    $c.Freeze()
    return $c
}

# Adds one moving picture to the loop. Whatever is passed in is already on
# screen showing its still version, so EVERY early return below still leaves a
# correct window - just a still one.
# -EveryMs is how long each frame stays up. The clock ticks every 50 ms, so
# 50 is 20 frames a second - what every picture drawn on 2026-09-23 or later
# is made for. The older wordmark fire asks for 100.
function Add-SpriteLoop($Image, [string]$SheetPath, [int]$FrameWidth, [int]$FrameHeight, [string]$Label, [int]$EveryMs = 50) {
    if ($null -eq $Image) { return }
    if ($FrameWidth -le 0 -or $FrameHeight -le 0) { return }
    if (-not (Test-Path -LiteralPath $SheetPath)) { return }
    try {
        $sheet = Get-PixelBitmap $SheetPath
        if ($null -eq $sheet) { return }
        $leaf = Split-Path -Leaf $SheetPath

        if ([int]$sheet.PixelWidth -ne $FrameWidth) {
            Log ("art: {0} is {1} wide but a frame is {2} - not animating {3}" -f $leaf, $sheet.PixelWidth, $FrameWidth, $Label)
            return
        }
        if (([int]$sheet.PixelHeight % $FrameHeight) -ne 0) {
            Log ("art: {0} is {1} tall, which is not a whole number of {2}px frames - not animating {3}" -f $leaf, $sheet.PixelHeight, $FrameHeight, $Label)
            return
        }
        $count = [int]([int]$sheet.PixelHeight / $FrameHeight)
        # 400, not 60, since 2026-09-23: the new strips are 120 frames (a
        # six second loop) and the mage is 160. Above 400 is still refused,
        # because that is a file somebody got wrong, not a longer animation.
        if ($count -lt 2 -or $count -gt 400) {
            Log ("art: {0} works out at {1} frames, which is not sensible - not animating {2}" -f $leaf, $count, $Label)
            return
        }

        $frames = New-Object System.Collections.ArrayList
        for ($i = 0; $i -lt $count; $i++) {
            [void]$frames.Add((Get-SpriteFrame $sheet 0 ($i * $FrameHeight) $FrameWidth $FrameHeight))
        }
        $every = [int][math]::Max(1, [math]::Round($EveryMs / $script:SpriteTickMs))
        [void]$script:spriteLoops.Add(@{ Img = $Image; Frames = $frames; Index = 0; Every = $every; Wait = 0 })
        Start-SpriteTimer
        Log ("art: {0} animating, {1} frames" -f $Label, $count)
    }
    catch { Log ("art: could not animate {0} - {1}" -f $Label, $_.Exception.Message) }
}

# The one timer. Started by the first Add-SpriteLoop and stopped when the
# window closes, so nothing is left ticking against a picture that is not on
# screen any more.
#
# To slow every moving picture down or speed them all up, change
# $script:SpriteTickMs above (and redraw the strips for the new speed).
function Start-SpriteTimer {
    if ($null -ne $script:spriteTimer) { return }
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds($script:SpriteTickMs)
    $timer.Add_Tick({
        # Script scope only. An event scriptblock in Windows PowerShell cannot
        # be trusted to see anything else.
        try {
            foreach ($loop in @($script:spriteLoops)) {
                if ($null -eq $loop) { continue }
                $fr = $loop.Frames
                if ($null -eq $fr -or $fr.Count -eq 0) { continue }
                $loop.Wait = [int]$loop.Wait + 1
                if ([int]$loop.Wait -lt [int]$loop.Every) { continue }
                $loop.Wait = 0
                $loop.Index = ([int]$loop.Index + 1) % $fr.Count
                $loop.Img.Source = $fr[[int]$loop.Index]
            }
        } catch { }
    })
    $timer.Start()
    $script:spriteTimer = $timer

    if ($null -ne $script:win) {
        $script:win.Add_Closed({
            try { if ($null -ne $script:spriteTimer) { $script:spriteTimer.Stop(); $script:spriteTimer = $null } } catch { }
        })
    }
}

# The wordmark's fire. wizard\wordmark-anim.png is the same picture as
# wordmark.png once per frame, stacked, with only the fire moving, and the
# movement LOOPS, so it can run round and round without a seam.
#
# The frame size comes from the still picture, which means swapping
# wordmark.png for a different size stops the animation instead of tearing it.
# To stop it on purpose, delete wordmark-anim.png.
function Start-WordmarkAnimation($StillImage) {
    if ($null -eq $script:brandWordmark -or $null -eq $StillImage) { return }
    Add-SpriteLoop $script:brandWordmark (Join-Path $WizardDir 'wordmark-anim.png') `
        ([int]$StillImage.PixelWidth) ([int]$StillImage.PixelHeight) 'the wordmark' 100
}


# --- the little picture on each tab -----------------------------------------
#  wizard\tab-<name>.png. The file name is the ONLY link between a picture and
#  its tab, so any of them can be redrawn, or deleted, without touching this
#  file.
#
#  THESE ARE DELIBERATELY STILL. They are about twenty pixels across, and
#  something that small moving in the corner of the eye is a distraction rather
#  than a decoration. The moving pictures are the big ones on the pages, below.
#  Nothing here looks for a tab-*-anim.png, so putting one on the drive does
#  nothing at all.
#
#  THE ORDER MATTERS and it is the tab order: play, health, profiles, saves,
#  features, help. It lines up with $script:tabIconImages, which is filled in
#  the same order in Show-MainWindow.
# THE TAB ORDER, by name, since 2026-10-10. Everything that picks a tab by
# number asks Get-TabIndex instead, so a new tab is one word here, in the
# XAML, and in the two picture lists below.
$script:TabOrder = @('play', 'profile', 'games', 'netplay', 'health', 'machine', 'saves', 'features', 'help')
function Get-TabIndex([string]$Name) {
    $i = [array]::IndexOf($script:TabOrder, ([string]$Name).ToLower())
    if ($i -lt 0) { return 0 }
    return $i
}

$script:TabIconFiles = @('tab-play', 'tab-profile', 'tab-games', 'tab-netplay', 'tab-health', 'tab-profiles',
                         'tab-saves', 'tab-features', 'tab-help')

function Initialize-TabIcons {
    if ($null -eq $script:tabIconImages) { return }
    for ($i = 0; $i -lt $script:TabIconFiles.Count; $i++) {
        if ($i -ge @($script:tabIconImages).Count) { break }
        $img = $script:tabIconImages[$i]
        if ($null -eq $img) { continue }
        $bmp = Get-PixelBitmap (Join-Path $WizardDir ([string]$script:TabIconFiles[$i] + '.png'))
        if ($null -eq $bmp) { continue }
        $img.Source = $bmp
    }
}


# --- the big picture in the corner of each page -----------------------------
#  wizard\page-<name>.png, and wizard\page-<name>-anim.png when it moves.
#  These are the ones with room to be looked at, so these are the ones that
#  move: the brew bubbles, the crystal ball turns, the chest glints.
#
#  Same order as the tabs, and PLAY HAS NONE ON PURPOSE - the mage and the
#  wordmark already own that page, and a third moving thing on it would be
#  noise rather than character. Its slot is an empty string.
#
#  Redrawn 2026-09-23 (docs\art\motion.py): every one now runs at 20 frames
#  a second on a six second loop, with small idle motion all the time and
#  one bigger moment per loop - the cork pops, the ball flares, the chest
#  lid bumps open, the brew bloops, a page turns.
#
#  Same two rules as everything else here: a missing file just leaves the
#  corner empty, and the frame count comes out of the strip's height rather
#  than being written down anywhere.
$script:PageArtFiles = @('', 'page-profile', 'page-games', 'page-netplay', 'page-health', 'page-profiles',
                         'page-saves', 'page-features', 'page-help')

function Initialize-PageArt {
    if ($null -eq $script:pageArtImages) { return }
    for ($i = 0; $i -lt $script:PageArtFiles.Count; $i++) {
        if ($i -ge @($script:pageArtImages).Count) { break }
        $stem = [string]$script:PageArtFiles[$i]
        if ($stem -eq '') { continue }
        $img = $script:pageArtImages[$i]
        if ($null -eq $img) { continue }
        $bmp = Get-PixelBitmap (Join-Path $WizardDir ($stem + '.png'))
        if ($null -eq $bmp) { continue }
        $img.Source = $bmp
        Add-SpriteLoop $img (Join-Path $WizardDir ($stem + '-anim.png')) `
            ([int]$bmp.PixelWidth) ([int]$bmp.PixelHeight) $stem
    }
    Update-HealthMargin
}


# --- the status lights ------------------------------------------------------
#  wizard\lights.png is one strip of four square gems, always in this order:
#  ok, warn, bad, unknown. A frame is as wide as the strip is tall, so the
#  strip has to be exactly four times as wide as it is high. That is the check
#  below, and it is why a wrong-shaped file cannot half-work - it either fits
#  or the plain dots come back.
#
#  THEY ARE DRAWN AT THEIR OWN SIZE. A 14px gem is shown 14px across, because
#  pixel art at any other size stops being square. Redraw the strip bigger and
#  the lights get bigger by themselves.
$script:LightOrder  = @('ok', 'warn', 'bad', 'unknown')
$script:LightFrames = $null
$script:LightsTried = $false

function Initialize-Lights {
    if ($script:LightsTried) { return }
    $script:LightsTried = $true

    $bmp = Get-PixelBitmap (Join-Path $WizardDir 'lights.png')
    if ($null -eq $bmp) { return }
    $h = [int]$bmp.PixelHeight
    $w = [int]$bmp.PixelWidth
    if ($h -le 0 -or $w -ne ($h * 4)) {
        Log ("art: lights.png is {0}x{1}, and it has to be four square frames wide - using plain dots" -f $w, $h)
        return
    }
    try {
        $frames = @{}
        for ($i = 0; $i -lt 4; $i++) {
            $frames[[string]$script:LightOrder[$i]] = (Get-SpriteFrame $bmp ($i * $h) 0 $h $h)
        }
        $script:LightFrames = $frames
        Log ("art: status lights loaded, {0}px" -f $h)
    }
    catch { Log ("art: could not cut up lights.png - {0}" -f $_.Exception.Message) }
}

# One light. Falls back to the plain coloured dot this used to draw, so a
# missing or wrong-shaped lights.png costs nothing at all.
function New-StatusLight([string]$State, [string]$Margin) {
    Initialize-Lights
    $key = [string]$State
    if ($script:LightOrder -notcontains $key) { $key = 'unknown' }

    if ($null -ne $script:LightFrames) {
        $img = New-Object System.Windows.Controls.Image
        $img.Source  = $script:LightFrames[$key]
        # Stretch None keeps it at its real size, which is the only way pixel
        # art stays square.
        $img.Stretch = 'None'
        $img.VerticalAlignment = 'Top'
        $img.Margin  = $Margin
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, [System.Windows.Media.BitmapScalingMode]::NearestNeighbor)
        return $img
    }

    $colour = $StatusColour[$key]
    if (-not $colour) { $colour = $StatusColour['unknown'] }
    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = 13; $dot.Height = 13
    $dot.Fill = (New-Brush $colour)
    $dot.Margin = $Margin
    return $dot
}


# The drive's logo and name at the top of the Play tab. Both are optional:
# a missing mage.png just means no picture, which is the same rule the
# feature switches follow - the worst a missing file can do is nothing.
function Initialize-Brand {
    if ($null -ne $script:brandName) { $script:brandName.Text = $WizardName }
    if ($null -ne $script:brandSub)  { $script:brandSub.Text  = "version $WizardVersion" }

    # The pixel wordmark replaces the plain text name when it is present, and
    # is simply skipped when it is not. Loaded BEFORE the mage below, because
    # the mage's own guard returns early and would otherwise skip this.
    $markPath = Join-Path $WizardDir 'wordmark.png'
    if ($null -ne $script:brandWordmark -and (Test-Path -LiteralPath $markPath)) {
        try {
            $wm = New-Object System.Windows.Media.Imaging.BitmapImage
            $wm.BeginInit()
            $wm.UriSource = New-Object System.Uri($markPath)
            # OnLoad like every other picture in this window: without it WPF
            # holds the file open, and a drive with an open file on it will
            # not eject.
            $wm.CacheOption = 'OnLoad'
            $wm.EndInit()
            $script:brandWordmark.Source = $wm
            $script:brandWordmark.Visibility = 'Visible'
            if ($null -ne $script:brandName) { $script:brandName.Visibility = 'Collapsed' }
            Start-WordmarkAnimation $wm
        }
        catch { Log ("logo: could not load wordmark.png - {0}" -f $_.Exception.Message) }
    }

    if ($null -eq $script:logoImage) { return }
    $logoPath = Join-Path $WizardDir 'mage.png'
    if (-not (Test-Path -LiteralPath $logoPath)) { Log 'logo: mage.png not found, carrying on'; return }
    try {
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.UriSource = New-Object System.Uri($logoPath)
        # OnLoad reads the picture now and lets the file go again. Without it
        # WPF holds the file open, and a drive with an open file on it will
        # not eject.
        $bmp.CacheOption = 'OnLoad'
        $bmp.EndInit()
        $script:logoImage.Source = $bmp

        # THE MAGE MOVES, since 2026-09-23. wizard\mage-anim.png is the mage
        # once per frame, 160 frames stacked, 20 a second: an eight second
        # loop of floating, blinking and drifting sparks, with one spell cast
        # near the end. Same rules as every other strip - same width as
        # mage.png, a whole number of frames tall, or it quietly stays still.
        # To stop it on purpose, delete mage-anim.png.
        Add-SpriteLoop $script:logoImage (Join-Path $WizardDir 'mage-anim.png') `
            ([int]$bmp.PixelWidth) ([int]$bmp.PixelHeight) 'the mage' 50
    }
    catch { Log ("logo: could not load mage.png - {0}" -f $_.Exception.Message) }
}


# ===========================================================================
#  MAKING THE PLAY PAGE FIT THE WINDOW
# ===========================================================================
#  The window can be dragged bigger or maximised, and until now nothing on it
#  grew with it: a tiny logo, a tiny Play button and a tiny line of health
#  text marooned in the middle of a television.
#
#  WHOLE NUMBERS ONLY, and that is the whole design. Every picture on this
#  page is pixel art drawn at NearestNeighbor, and pixel art only survives
#  being scaled by 1, 2 or 3. At 1.5 some source pixels come out two screen
#  pixels wide and their neighbours come out one, which reads as a wobble -
#  worse than not growing at all, and much worse in the wordmark's fire,
#  where it would wobble twelve times a second.
#
#  So the size steps rather than stretches. The thresholds below are the
#  window sizes at which there is genuinely room for the next step up; a
#  maximised window on a 1080p screen lands on x2, which is the case this
#  was asked for.
#
#  The Play button is the exception that proves it: it is drawn out of plain
#  rectangles by the PixelButton style, not from a picture, so any size at
#  all is crisp and it simply grows with the step.
#
#  IT CAN NEVER BE THE PROBLEM. The whole body is wrapped and every element
#  is checked for $null first, so a missing picture or an early size event
#  leaves the page exactly as it was.
# ---------------------------------------------------------------------------
$script:playScale = 0
$script:playDpi   = 0.0
$script:playSoft  = 0.0
$script:playArtK  = 0
$script:playGem   = $null
$script:playTexts = @()

# What Windows is scaling this screen by: 1.0, 1.25, 1.5, 2.0 and so on.
# Returns 1.0 if it cannot be worked out, which is the harmless answer.
function Get-DpiScale {
    try {
        $src = [System.Windows.PresentationSource]::FromVisual($script:win)
        if ($null -ne $src -and $null -ne $src.CompositionTarget) {
            $m = [double]$src.CompositionTarget.TransformToDevice.M11
            if ($m -gt 0.1 -and $m -lt 8) { return $m }
        }
    }
    catch { }
    return 1.0
}

# THE HEALTH TAB'S RIGHT EDGE (2026-09-23). The potions sit in that page's
# bottom-right corner behind the list, and on a small window the check cards
# ran right over them. So the list stops short of them: its right margin is
# the potions' width as currently drawn, plus a gap. Only the Health tab does
# this - on the other tabs the picture is allowed to sit behind the page.
$script:artRatio = 1.0
function Update-HealthMargin {
    try {
        if ($null -eq $script:healthPanel -or $null -eq $script:pageArtImages) { return }
        $img = @($script:pageArtImages)[(Get-TabIndex 'health')]
        if ($null -eq $img -or $null -eq $img.Source) { return }
        $aw = [double]$img.Source.PixelWidth * [double]$script:artRatio
        $script:healthPanel.Margin = New-Object System.Windows.Thickness(6, 0, ($aw + 18), 0)
    }
    catch { Log ("health margin: {0}" -f $_.Exception.Message) }
}

function Update-PlayScale {
    [CmdletBinding()]
    param([switch]$Force)

    if ($null -eq $script:win) { return }
    try {
        $w = [double]$script:win.ActualWidth
        $h = [double]$script:win.ActualHeight
        if ($w -le 0 -or $h -le 0) { return }

        $dpi = Get-DpiScale

        # THE SIZE STEP. Measured in the units WPF works in, which are NOT
        # screen pixels: on a screen set to 150% a maximised 1920x1080 window
        # reports about 1280 x 693 here. The first version of this asked for
        # 840 and so never grew on a scaled screen at all - which is exactly
        # what happened. These numbers are what a x2 Play page actually needs:
        # about 860 across and 620 down, plus the tab strip and the footer.
        #
        # CHANGED 2026-09-23, because maximised was far too big. The step used
        # to go to x2 as soon as the window reached about 1000 x 680, which
        # on Steven's laptop (125%) meant every picture tripled - 1 screen
        # pixel each to 3 - and the Play button nearly doubled. Now:
        #
        #   $grow  how much bigger the window is than its normal 800 x 620,
        #          by whichever side grew LESS (a wide, short window has not
        #          really got more room).
        #   $k     pictures only step up when there is room for a whole
        #          second copy of the page, i.e. $grow of 2 or more. Pixel
        #          art cannot grow "a little" - x1.2 is exactly the wobble
        #          described above - so it waits for real space.
        #   $soft  the Play button and the text, which are not pixel art and
        #          CAN grow a little: half as fast as the window, at most
        #          +35%. Maximised on a laptop this comes out at about +13%.
        $grow = [math]::Min($w / 800.0, $h / 620.0)
        $k = 1
        if ($grow -ge 2.0) { $k = 2 }
        if ($grow -ge 3.0) { $k = 3 }
        $soft = 1.0 + [math]::Min(0.35, [math]::Max(0.0, ($grow - 1.0) * 0.5))
        $soft = [math]::Round($soft, 2)

        # ADDED 2026-09-23 (second pass). $k above waits for double the room,
        # which on a laptop means never, so maximised looked like nothing
        # scaled at all. The PICTURES - the mage, the wordmark, the controller
        # button and every page's corner picture - now take their own step
        # as soon as the window is 20% bigger than normal: x2 screen pixels
        # each, and x3 on something the size of a TV. Still whole numbers,
        # so still sharp. The Play button and the text keep the gentle $soft.
        $artK = 1
        if ($grow -ge 1.2) { $artK = 2 }
        if ($grow -ge 2.2) { $artK = 3 }

        if ($k -eq $script:playScale -and $dpi -eq $script:playDpi -and $soft -eq $script:playSoft -and $artK -eq $script:playArtK -and -not $Force) { return }
        $changed = ($k -ne $script:playScale -or $dpi -ne $script:playDpi -or $soft -ne $script:playSoft -or $artK -ne $script:playArtK)
        $script:playScale = $k
        $script:playDpi   = $dpi
        $script:playSoft  = $soft
        $script:playArtK  = $artK

        # THE OTHER HALF, and the reason the mage looked soft. Pixel art only
        # stays sharp when one of its pixels lands on a whole number of SCREEN
        # pixels. WPF sizes everything in its own units and Windows then
        # multiplies by the display scale, so at 150% a picture asked for at
        # its natural size is drawn at 1.5 screen pixels per art pixel - half
        # of them one size, half another. That is the blur.
        #
        # So the scale actually applied is chosen to come out whole AFTER
        # Windows has multiplied:  round(k x dpi) / dpi.
        #    100%: 1/1   = 1.00 -> 1 screen pixel each. Unchanged.
        #    125%: 1/1.25 = 0.80 -> 1 screen pixel each.
        #    150%: 2/1.5  = 1.33 -> 2 screen pixels each. Sharp, and bigger.
        #    200%: 2/2   = 1.00 -> 2 screen pixels each.
        # AwayFromZero, not .NET's default. The default rounds a half to the
        # nearest EVEN number, so 4.5 becomes 4 and 5.5 becomes 6 - which is
        # correct arithmetic and an unpredictable size step. Either answer is
        # a whole number and so either is sharp; this one is just the one
        # anybody reading it would expect.
        $dev   = [math]::Max(1, [math]::Round($k * $dpi, [System.MidpointRounding]::AwayFromZero))
        $art   = $dev / $dpi
        $scale = New-Object System.Windows.Media.ScaleTransform($art, $art)

        # Every pixel picture, through the SAME transform. A LayoutTransform
        # rather than a RenderTransform, because that one also tells the
        # layout how much room the picture now takes - a RenderTransform would
        # draw it bigger and leave a hole where it used to be.
        # The big pictures use $artK. One screen pixel per art pixel is
        # round(dpi) (1 at 100% and 125%, 2 at 150% and 200%), times the step.
        $devArt   = $artK * [math]::Max(1, [math]::Round($dpi, [System.MidpointRounding]::AwayFromZero))
        $artScale = New-Object System.Windows.Media.ScaleTransform(($devArt / $dpi), ($devArt / $dpi))
        foreach ($img in @($script:logoImage, $script:brandWordmark, $script:padImage)) {
            if ($null -ne $img) { $img.LayoutTransform = $artScale }
        }
        foreach ($img in @($script:pageArtImages)) {
            if ($null -ne $img) { $img.LayoutTransform = $artScale }
        }
        $script:artRatio = $devArt / $dpi
        Update-HealthMargin

        # The little status gem stays with the old step - it sits in a line
        # of text and a doubled gem next to +13% text looks wrong.
        if ($null -ne $script:playGem) { $script:playGem.LayoutTransform = $scale }

        # Text is not pixel art, so it can be any size at all.
        # Grows with $soft (a little) until the pictures take a real step,
        # then keeps pace with them. Never the old flat +13 / +6 jumps.
        $tk = [math]::Max($soft, [double]$k)
        if ($null -ne $script:brandName) { $script:brandName.FontSize = [math]::Round(23 * $tk) }
        if ($null -ne $script:brandSub)  { $script:brandSub.FontSize  = [math]::Round(13 * $tk) }
        foreach ($t in @($script:playTexts)) {
            if ($null -ne $t) { $t.FontSize = [math]::Round(14 * $tk) }
        }

        # The Play button is drawn from plain rectangles by the PixelButton
        # style, not from a picture, so any size at all is crisp.
        if ($null -ne $script:playButton) {
            $script:playButton.Width    = [math]::Round(300 * $tk)
            $script:playButton.Height   = [math]::Round(106 * $tk)
            $script:playButton.FontSize = [math]::Round(34  * $tk)
        }
        if ($changed) {
            Log ("window {0:N0} x {1:N0} at {2}% -> size step x{3}, pictures x{4:N2} ({5} screen pixels each), button and text x{6:N2}, big pictures {7} screen pixels each" -f `
                 $w, $h, [int]($dpi * 100), $k, $art, $dev, [math]::Max($soft, [double]$k), $devArt)
        }
    }
    catch { Log ("scale: {0}" -f $_.Exception.Message) }
}


# The controller picture on the Play tab's button. Optional like every other
# picture here: no wizard\controllers.png and the button is simply an empty
# grey box that still opens the controller list.
function Initialize-PadIcon {
    if ($null -eq $script:padImage) { return }
    $bmp = Get-PixelBitmap (Join-Path $WizardDir 'controllers.png')
    if ($null -eq $bmp) { Log 'art: controllers.png not found, the pad button keeps its box'; return }
    $script:padImage.Source = $bmp
}


# --- TEST-SLICE-START: health summary --------------------------------------
#  Turns the seven checks into the one line the Play tab shows. Deliberately
#  PURE - no WPF, no files, no $script: state - so the test harness can cut
#  this exact block out of this file and run it against the real status.json
#  without needing a window. Because it is sliced out of the shipping file
#  rather than copied, the tests follow any future edit.
#
#  'unknown' counts as needing a look, the same way the health check's own
#  overall does. A check that could not run is not a check that passed.
function Get-HealthSummary($s) {
    $bad = @(); $warn = @()
    foreach ($p in $s.checks.PSObject.Properties) {
        switch ([string]$p.Value.status) {
            'bad'     { $bad  += [string]$p.Value.title }
            'warn'    { $warn += [string]$p.Value.title }
            'unknown' { $warn += [string]$p.Value.title }
        }
    }
    # @() around the count, because a property on an empty result is not 0
    # and $null.Count is not 0 either.
    $total = @($s.checks.PSObject.Properties).Count
    $named = @($bad + $warn)

    $state = 'ok'
    if ($bad.Count -gt 0) { $state = 'bad' }
    elseif ($warn.Count -gt 0) { $state = 'warn' }

    if ($state -eq 'ok') { $line = "All $total checks passed." }
    else { $line = "{0} of {1} need a look: {2}." -f $named.Count, $total, ($named -join ', ') }

    return @{ State = $state; Line = $line; Total = $total; Named = $named }
}
# --- TEST-SLICE-END: health summary ----------------------------------------


# ONE light on the Play tab, summarising all seven. The detail did not go
# anywhere: it is the Health tab, which still has every check, its own
# wording and its fix buttons. Anything that is not green names itself here
# and points at that tab, so the front page stays one thing to read.
function Render-PlaySummary($s) {
    $sum   = Get-HealthSummary $s
    $state = [string]$sum.State
    $line  = [string]$sum.Line

    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.HorizontalAlignment = 'Center'
    $gem = New-StatusLight $state '0,3,12,0'
    $lab = New-Text 'Drive health' $ColText 14 $true
    [void]$row.Children.Add($gem)
    [void]$row.Children.Add($lab)
    $t = New-Text $line $ColDim 14
    $t.Margin = '10,0,0,0'; $t.MaxWidth = 520
    [void]$row.Children.Add($t)
    [void]$script:lightsPanel.Children.Add($row)

    # Handed to Update-PlayScale, which is the only thing that resizes them.
    # Kept here rather than found by name because this row is built in code,
    # not in the XAML, so there is no name to find it by.
    $script:playGem   = $gem
    $script:playTexts = @($lab, $t)
    Update-PlayScale -Force

    if ($state -ne 'ok') {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = 'Open the Health tab'; $b.Padding = '12,5'; $b.FontSize = 13
        $b.Margin = '0,10,0,0'; $b.HorizontalAlignment = 'Center'
        $b.Add_Click({ $script:tabs.SelectedIndex = (Get-TabIndex 'health') })
        [void]$script:lightsPanel.Children.Add($b)
    }
}


# The Help tab. Every word comes from scripts\HelpText.ps1, which is also
# what Maintenance Steps\Show Help.bat prints, so the tab and the button can
# never disagree. If that file is missing the tab says where to read instead
# of being blank.
# The "set this computer up" button, and anything else the Help tab can DO
# rather than say. It is a separate function because Render-Help returns early
# in two places and the button has to appear on all three paths - somebody
# whose HelpText.ps1 is missing still needs to be able to set their computer
# up.
function Add-HelpActions {
    if ($null -eq $script:helpPanel) { return }

    Add-UpdateActions
    Add-BugAction

    # Each button below stands on its own: a missing LocalSetup.ps1 must not
    # take the rename button away with it, and the other way round.
    if ($script:localSetupOk) {
        $row = New-Object System.Windows.Controls.StackPanel
        $row.Orientation = 'Horizontal'; $row.Margin = '0,16,0,0'

        $b = New-Object System.Windows.Controls.Button
        $b.Padding = '10,3'; $b.FontSize = 13; $b.VerticalAlignment = 'Top'   # Top: the row would otherwise stretch it to the height of the text beside it
        if (Test-LocalSetupInstalled) { $b.Content = 'Set this computer up again' }
        else                          { $b.Content = 'Set this computer up' }
        $b.Add_Click({ Invoke-LocalSetup })
        [void]$row.Children.Add($b)

        $t = New-Text 'Puts Play, this wizard and a Controllers button on this computer, with icons that stay put when the drive is unplugged.' $ColDim 13
        $t.Margin = '12,7,0,0'; $t.MaxWidth = 470; $t.TextWrapping = 'Wrap'
        [void]$row.Children.Add($t)

        [void]$script:helpPanel.Children.Add($row)
    }

    # --- a shortcut to one game -------------------------------------------
    #  It sits beside "set this computer up" because it is the same kind of
    #  job: something written onto the COMPUTER, not onto the drive.
    if ($script:shortcutMakerOk) {
        $row2 = New-Object System.Windows.Controls.StackPanel
        $row2.Orientation = 'Horizontal'; $row2.Margin = '0,16,0,0'

        $b2 = New-Object System.Windows.Controls.Button
        $b2.Content = 'Add a shortcut to a game'
        $b2.Padding = '10,3'; $b2.FontSize = 13; $b2.VerticalAlignment = 'Top'   # Top: the row would otherwise stretch it to the height of the text beside it
        $b2.Add_Click({ Invoke-ShortcutMakerFromWizard })
        [void]$row2.Children.Add($b2)

        $t2 = New-Text 'Puts one game on the desktop or Start Menu, with its own artwork as the icon. You choose which picture, because box art and logos read very differently once they are icon sized.' $ColDim 13
        $t2.Margin = '12,7,0,0'; $t2.MaxWidth = 470; $t2.TextWrapping = 'Wrap'
        [void]$row2.Children.Add($t2)

        [void]$script:helpPanel.Children.Add($row2)
    }

    # --- the drive letter --------------------------------------------------
    #  Only drawn when there is something to do. On a computer where the drive
    #  is already R:, or where R: belongs to somebody else, a button offering
    #  it would be a dead end.
    if ($script:driveLetterOk) {
        $dls = $null
        try { $dls = Get-DriveLetterStatus -Root $Root } catch { }
        if ($null -ne $dls -and ($dls.State -eq 'canchange' -or $dls.State -eq 'needsadmin')) {
            $row3 = New-Object System.Windows.Controls.StackPanel
            $row3.Orientation = 'Horizontal'; $row3.Margin = '0,16,0,0'

            $b3 = New-Object System.Windows.Controls.Button
            $b3.Content = 'Make this drive R:'
            $b3.Padding = '10,3'; $b3.FontSize = 13; $b3.VerticalAlignment = 'Top'   # Top: the row would otherwise stretch it to the height of the text beside it
            $b3.Add_Click({ Invoke-DriveLetterFromWizard })
            [void]$row3.Children.Add($b3)

            $why = $dls.Line + ' Nothing here needs it - it is a safety net for the odd emulator setting that insists on a letter.'
            $t3 = New-Text $why $ColDim 13
            $t3.Margin = '12,7,0,0'; $t3.MaxWidth = 470; $t3.TextWrapping = 'Wrap'
            [void]$row3.Children.Add($t3)

            [void]$script:helpPanel.Children.Add($row3)
        }
    }

    Add-RenameAction
}


# The drive's name lives in ONE place, the name line in wizard\wizard.ini, and
# everything follows it by itself - except the .bat file at the top of the
# drive, because a file cannot rename itself while Windows is running it. This
# is that one exception, as a button.
#
# The old .bat is MOVED into _ClaudeWorkspace\_SAFE TO DELETE\, never deleted,
# which is this drive's rule for everything.
function Add-RenameAction {
    if ($null -eq $script:helpPanel) { return }
    if (-not (Test-Path -LiteralPath (Join-Path $ScriptsDir 'Rename-WizardButton.ps1'))) { return }

    # Tucked inside an Expander since 2026-09-18. It is a real button that
    # does a real job, but that job only exists for somebody who has renamed
    # the whole drive in wizard\wizard.ini - which is once, ever, and
    # probably never. On the open page it read like something you were
    # supposed to do.
    $exp = New-Object System.Windows.Controls.Expander
    $exp.Margin = '0,18,0,0'; $exp.FontSize = 14
    $exp.Foreground = (New-Brush $ColDim)
    $exp.Header = 'Advanced'

    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.Margin = '0,8,0,0'

    $b = New-Object System.Windows.Controls.Button
    $b.Content = 'Rename the button at the top of the drive'
    $b.Padding = '10,3'; $b.FontSize = 13; $b.VerticalAlignment = 'Top'   # Top: the row would otherwise stretch it to the height of the text beside it
    $b.Add_Click({
        if (Test-RetroBatRunning) {
            [void](Show-Choice $WizardName 'RetroBat is open. Close it completely first - Windows will not rename a file that something else is holding.' @('OK'))
            return
        }
        $code = Invoke-Step 'Rename-WizardButton.ps1' 'renaming the wizard button'
        if ($code -eq 0) {
            [void](Show-Choice $WizardName ("Done.`n`nThe button at the top of the drive now matches the name in wizard\wizard.ini. The old one was moved into _ClaudeWorkspace\_SAFE TO DELETE - nothing was deleted.") @('OK'))
        }
        else {
            [void](Show-Choice $WizardName ("That did not finish, and nothing was left half-done.`n`nThe details are in wizard.log.") @('OK'))
        }
    })
    [void]$row.Children.Add($b)

    $t = New-Text 'Only needed after the drive is given a new name in wizard\wizard.ini. A file cannot rename itself while Windows is running it, which is the whole reason this is a button.' $ColDim 13
    $t.Margin = '12,7,0,0'; $t.MaxWidth = 420; $t.TextWrapping = 'Wrap'
    [void]$row.Children.Add($t)

    $exp.Content = $row
    [void]$script:helpPanel.Children.Add($exp)
}


# Asks, then does it. Everything here is written to the COMPUTER and nothing
# to the drive, so there is no "close RetroBat first" and nothing to undo on
# the drive if it goes wrong.
function Invoke-LocalSetup {
    if (-not $script:localSetupOk) { return }

    $current = @()
    try { $current = @(Get-LocalSetupPlaces -WizardName $WizardName) } catch { }
    $already = ($current.Count -gt 0)

    if ($already) {
        $msg = "Where should this computer's buttons be?`n`nSaving also points them at wherever the drive is plugged in right now, which is what fixes them after the drive changes letter."
    }
    else {
        $msg = "Add Play, this wizard and a Controllers button to this computer?`n`nThe icons are copied onto the computer so they stay put when the drive is unplugged. Nothing at all is written to the drive."
    }

    $ans = Show-PlaceToggles $WizardName $msg $current
    if (-not $ans.Ok) { return }
    $places = @($ans.Places)

    # Both switched off means take them away, which is a real answer and the
    # only one that needs asking twice.
    if ($places.Count -eq 0) {
        if (-not $already) { return }
        $sure = Show-Choice $WizardName "Take this computer's buttons away?`n`nThe drive is untouched and still works from PLAY.bat and SETUP RETROBAT.bat at the top of it." @('Take them away', 'Cancel')
        if ($sure -ne 'Take them away') { return }
        $r = Remove-LocalSetup -Logger { param($m) Log $m }
        [void](Show-Choice $WizardName ("Removed {0} buttons from this computer.`n`nThe drive itself is untouched." -f @($r.Removed).Count) @('OK'))
        Render-Help
        return
    }

    $res = Install-LocalSetup -Root $Root -WizardName $WizardName -Places $places -Logger { param($m) Log $m }

    if ([string]$res.Problem -ne '') {
        [void](Show-Choice $WizardName ("It did not work: {0}`n`nNothing was changed. Details are in wizard.log." -f $res.Problem) @('OK'))
        return
    }

    $made = 0
    foreach ($k in @($res.Results.Keys)) {
        $v = [string]$res.Results[$k]
        if ($v -eq 'written' -or $v -eq 'unchanged') { $made++ }
    }

    [void](Show-Choice $WizardName ("{0} buttons are on this computer now.`n`nTo pin one to Start or the taskbar, open Start, find the {1} folder, right-click a button and choose Pin. Windows will not let a script do that part." -f $made, $WizardName) @('OK'))
    Render-Help
}


# ===========================================================================
#  THE GAMES TAB                                                 (2026-10-10)
# ===========================================================================
#  Add a game from this computer, and the online library Steven fills. The
#  engine is scripts\GameLibrary.ps1, which explains both.
#
#  Copies and downloads report progress on the tab itself. A download runs
#  in a second runspace so the window stays alive; a copy from this computer
#  runs here, pumping the window between pieces, because it is the person's
#  own file and they are watching it.
# ---------------------------------------------------------------------------
$script:libCatalog   = $null
$script:libNote      = ''
$script:libBusy      = @{}       # game id -> 'Downloading...'
$script:libJobs      = @()       # running downloads
$script:libTimer     = $null
$script:gamesSystems = $null

function Get-GamesSystems {
    if ($null -eq $script:gamesSystems) {
        try { $script:gamesSystems = @(Get-LibSystems $Root) } catch { Log "games: could not read es_systems.cfg - $_"; $script:gamesSystems = @() }
    }
    return $script:gamesSystems
}

function Set-GamesStatus([string]$Text) {
    if ($null -ne $script:gamesStatus) {
        $script:gamesStatus.Text = $Text
        try { $script:win.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) } catch { }
    }
}

# A short list to pick one console from. Returns the system or $null.
function Show-ConsolePick([string]$Message, $Systems) {
    Close-Splash
    $w = New-Object System.Windows.Window
    $w.Title = $WizardName; $w.Width = 460; $w.Height = 420
    $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'NoResize'
    $w.Background = (New-Brush $ColBg); $w.Topmost = $true
    $dp = New-Object System.Windows.Controls.DockPanel; $dp.Margin = '20'
    $msg = New-Text $Message $ColText 14; $msg.TextWrapping = 'Wrap'; $msg.Margin = '0,0,0,12'
    [System.Windows.Controls.DockPanel]::SetDock($msg, 'Top'); [void]$dp.Children.Add($msg)
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.HorizontalAlignment = 'Right'; $row.Margin = '0,12,0,0'
    [System.Windows.Controls.DockPanel]::SetDock($row, 'Bottom')
    $lb = New-Object System.Windows.Controls.ListBox; $lb.FontSize = 13
    foreach ($s in @($Systems)) { [void]$lb.Items.Add([string]$s.FullName) }
    if ($lb.Items.Count -gt 0) { $lb.SelectedIndex = 0 }
    $script:cpList = $lb; $script:cpWin = $w; $script:cpOk = $false
    $lb.Add_MouseDoubleClick({ $script:cpOk = $true; $script:cpWin.Close() })
    foreach ($pair in @(@('Cancel', $false), @('Use this console', $true))) {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $pair[0]; $b.Tag = $pair[1]; $b.Margin = '8,0,0,0'; $b.Padding = '14,6'; $b.FontSize = 14
        $b.Add_Click({ param($s2, $e2) $script:cpOk = [bool]$s2.Tag; $script:cpWin.Close() })
        [void]$row.Children.Add($b)
    }
    [void]$dp.Children.Add($row); [void]$dp.Children.Add($lb)
    $w.Content = $dp
    [void]$w.ShowDialog()
    if (-not $script:cpOk -or $script:cpList.SelectedIndex -lt 0) { return $null }
    return @($Systems)[$script:cpList.SelectedIndex]
}

# Which console for this file: sure answers straight through, otherwise ask.
function Resolve-GameConsole([string]$File) {
    $systems = Get-GamesSystems
    $g = Get-LibSystemGuess $File $systems
    $name = [System.IO.Path]::GetFileName($File)
    if (@($g.Candidates).Count -eq 0) {
        $pick = Show-ConsolePick ("RetroBat does not know what '$name' is from its file type. If you know which console it is for, pick it:") $systems
        return $pick
    }
    if ($g.Sure) { return @($g.Candidates)[0] }
    return (Show-ConsolePick ("Which console is '$name' for?") @($g.Candidates))
}

function Invoke-AddGames {
    try {
        Add-Type -AssemblyName PresentationFramework
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Title = 'Choose game files to add'; $dlg.Multiselect = $true
        $dlg.Filter = 'Game files|*.*'
        if (-not $dlg.ShowDialog()) { return }
    } catch { Log "games: file dialog - $_"; return }
    $done = @(); $skipped = @(); $failed = @()
    foreach ($f in @($dlg.FileNames)) {
        $sys = Resolve-GameConsole $f
        $leaf = [System.IO.Path]::GetFileName($f)
        if ($null -eq $sys) { $skipped += $leaf; continue }
        $script:gamesCopyName = $leaf
        $r = Add-LibGameFile $f $sys { param($p) Set-GamesStatus ("Copying {0}... {1}%" -f $script:gamesCopyName, $p) }
        if ($r.Ok) { $done += ("{0}  ({1}){2}" -f $leaf, $sys.FullName, $(if ($r.Message -eq 'Already there.') { ' - already there' } else { '' })); Log ("games: added {0} to {1}" -f $leaf, $sys.Name) }
        else { $failed += ("{0}: {1}" -f $leaf, $r.Message); Log ("games: could not add {0} - {1}" -f $leaf, $r.Message) }
    }
    Set-GamesStatus ''
    $msg = ''
    if ($done.Count -gt 0)    { $msg += "Added:`n" + (($done | ForEach-Object { "  $_" }) -join "`n") + "`n`nThey show up the next time RetroBat starts. For box art and videos, open RetroBat's menu (START) > SCRAPER." }
    if ($failed.Count -gt 0)  { $msg += "`n`nNot added:`n" + (($failed | ForEach-Object { "  $_" }) -join "`n") }
    if ($skipped.Count -gt 0) { $msg += "`n`nSkipped (no console picked): " + ($skipped -join ', ') }
    if ($msg -ne '') { [void](Show-ChoiceScroll $WizardName $msg.Trim()) }
    Render-Games
}

# Show-Choice, but the text can be long (a list of games).
function Show-ChoiceScroll([string]$Title, [string]$Message) {
    $w = New-Object System.Windows.Window
    $w.Title = $Title; $w.Width = 560; $w.Height = 420
    $w.WindowStartupLocation = 'CenterScreen'; $w.Background = (New-Brush $ColBg); $w.Topmost = $true
    $dp = New-Object System.Windows.Controls.DockPanel; $dp.Margin = '20'
    $ok = New-Object System.Windows.Controls.Button
    $ok.Content = 'OK'; $ok.Padding = '18,6'; $ok.FontSize = 14; $ok.HorizontalAlignment = 'Right'; $ok.Margin = '0,12,0,0'
    $script:csWin = $w
    $ok.Add_Click({ $script:csWin.Close() })
    [System.Windows.Controls.DockPanel]::SetDock($ok, 'Bottom'); [void]$dp.Children.Add($ok)
    $sv = New-Object System.Windows.Controls.ScrollViewer; $sv.VerticalScrollBarVisibility = 'Auto'
    $t = New-Text $Message $ColText 14; $t.TextWrapping = 'Wrap'
    $sv.Content = $t; [void]$dp.Children.Add($sv)
    $w.Content = $dp
    [void]$w.ShowDialog()
}

# --- the online library ------------------------------------------------------
function Start-LibraryJob([string]$Kind, $Game = $null) {
    try {
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        try { $iss.ExecutionPolicy = 'Bypass' } catch { }
        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
        $rs.Open()
        $ps = [System.Management.Automation.PowerShell]::Create(); $ps.Runspace = $rs
        $lib = Join-Path $ScriptsDir 'GameLibrary.ps1'
        if ($Kind -eq 'catalog') {
            [void]$ps.AddScript('param($lib, $ws) . $lib; Get-LibCatalog $ws').AddArgument($lib).AddArgument($Ws)
        }
        else {
            [void]$ps.AddScript('param($lib, $ws, $root, $game) . $lib; $s = @(Get-LibSystems $root); Install-LibGame $ws $game $s').AddArgument($lib).AddArgument($Ws).AddArgument($Root).AddArgument($Game)
        }
        $script:libJobs += [pscustomobject]@{ Kind = $Kind; Game = $Game; Ps = $ps; Handle = $ps.BeginInvoke() }
        if ($null -eq $script:libTimer) {
            $script:libTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:libTimer.Interval = [TimeSpan]::FromMilliseconds(700)
            $script:libTimer.Add_Tick({ Invoke-LibraryTick })
        }
        $script:libTimer.Start()
    }
    catch { Log ("library: could not start - {0}" -f $_.Exception.Message) }
}

function Invoke-LibraryTick {
    try {
        $still = @()
        $redraw = $false
        foreach ($j in @($script:libJobs)) {
            if (-not $j.Handle.IsCompleted) { $still += $j; continue }
            $out = $null
            try { $out = @($j.Ps.EndInvoke($j.Handle)) } catch { $out = @(@{ Ok = $false; Message = $_.Exception.Message }) }
            try { $j.Ps.Runspace.Dispose(); $j.Ps.Dispose() } catch { }
            $r = $(if ($out.Count -gt 0) { $out[-1] } else { @{ Ok = $false; Message = 'No answer.' } })
            if ($j.Kind -eq 'catalog') {
                $script:libCatalog = $r
                $script:libNote = $(if ($r.Ok) { $(if ($r.Message) { $r.Message } else { 'Updated ' + (Get-Date -Format 'h:mm tt') + '.' }) } else { $r.Message })
            }
            else {
                $script:libBusy.Remove($j.Game.Id)
                Log ("library: {0} - {1}" -f $j.Game.Title, $r.Message)
                $script:libNote = $r.Message
            }
            $redraw = $true
        }
        $script:libJobs = $still
        if ($still.Count -eq 0) { $script:libTimer.Stop() }
        if ($redraw) { Render-Games }
    }
    catch { Log ("library tick: {0}" -f $_.Exception.Message) }
}

function Invoke-LibraryAdd($Game) {
    if ($script:libBusy.ContainsKey($Game.Id)) { return }
    $mb = [math]::Round($Game.Size / 1MB, 1)
    $pick = Show-Choice $WizardName ("Add {0} to your drive?`n`n{1} MB download. It goes into the {2} folder and shows up the next time RetroBat starts." -f $Game.Title, $mb, $Game.System) @('Add it', 'Cancel')
    if ($pick -ne 'Add it') { return }
    $script:libBusy[$Game.Id] = 'Downloading...'
    Start-LibraryJob 'install' $Game
    Render-Games
}

function Render-Games {
    $panel = $script:gamesPanel
    if ($null -eq $panel) { return }
    $panel.Children.Clear()
    if (-not $script:gamesOk) {
        [void]$panel.Children.Add((New-Text 'scripts\GameLibrary.ps1 is missing, so this tab is empty.' $ColDim 14))
        return
    }

    [void]$panel.Children.Add((New-IconHeader 'E898' 'Add a game from this computer'))
    $t = New-Text 'Pick game files you own. Each is copied (not moved) into the right console''s folder; when the file type could be more than one console, you are asked. They show up the next time RetroBat starts.' $ColDim 13
    $t.TextWrapping = 'Wrap'
    [void]$panel.Children.Add($t)
    $ab = New-Object System.Windows.Controls.Button
    $ab.Content = 'Choose game files...'; $ab.Padding = '14,6'; $ab.FontSize = 14; $ab.FontWeight = 'Bold'
    $ab.HorizontalAlignment = 'Left'; $ab.Margin = '0,10,0,0'
    $ab.Add_Click({ Invoke-AddGames })
    [void]$panel.Children.Add($ab)
    $st = New-Text '' $ColAway 13; $st.Margin = '0,6,0,0'
    $script:gamesStatus = $st
    [void]$panel.Children.Add($st)

    # --- the online library -------------------------------------------------
    [void]$panel.Children.Add((New-IconHeader 'E896' 'Online library'))
    $lt = New-Text 'Free, homebrew and fan-made games, picked out and put online for you. Add any you like.' $ColDim 13
    $lt.TextWrapping = 'Wrap'
    [void]$panel.Children.Add($lt)
    $cat = $script:libCatalog
    if ($null -eq $cat) {
        [void]$panel.Children.Add((New-Text 'Loading...' $ColDim 13))
        if (@($script:libJobs | Where-Object Kind -eq 'catalog').Count -eq 0) { Start-LibraryJob 'catalog' }
    }
    elseif (-not $cat.Ok) {
        [void]$panel.Children.Add((New-Text ([string]$cat.Message) $ColAway 13))
    }
    elseif (@($cat.Games).Count -eq 0) {
        [void]$panel.Children.Add((New-Text 'Nothing in the library yet. Check back soon.' $ColDim 13))
    }
    else {
        $systems = Get-GamesSystems
        $lastSys = ''
        foreach ($g in @($cat.Games)) {
            if ($g.System -ne $lastSys) {
                $lastSys = $g.System
                $full = @($systems | Where-Object Name -eq $g.System | ForEach-Object FullName)
                $h = New-Text $(if ($full.Count -gt 0) { $full[0] } else { $g.System.ToUpper() }) $ColText 14 $true
                $h.Margin = '0,12,0,2'
                [void]$panel.Children.Add($h)
            }
            $row = New-Object System.Windows.Controls.DockPanel; $row.Margin = '0,6,0,0'
            $right = New-Object System.Windows.Controls.StackPanel; $right.Orientation = 'Horizontal'; $right.VerticalAlignment = 'Top'
            [System.Windows.Controls.DockPanel]::SetDock($right, 'Right')
            if ($script:libBusy.ContainsKey($g.Id)) { [void]$right.Children.Add((New-Text $script:libBusy[$g.Id] $ColAway 12)) }
            elseif (Test-LibGameInstalled $g $systems) { [void]$right.Children.Add((New-Text 'On your drive' $ColOnline 12)) }
            else {
                $b = New-Object System.Windows.Controls.Button
                $b.Content = 'Add to my drive'; $b.Padding = '10,3'; $b.FontSize = 13; $b.Tag = $g
                $b.Add_Click({ param($s2, $e2) Invoke-LibraryAdd $s2.Tag })
                [void]$right.Children.Add($b)
            }
            [void]$row.Children.Add($right)
            $info = New-Object System.Windows.Controls.StackPanel; $info.Margin = '0,0,12,0'
            $meta = @()
            if ($g.Players -ne '') { $meta += ('{0} players' -f $g.Players) }
            $meta += ('{0} MB' -f [math]::Round($g.Size / 1MB, 1))
            [void]$info.Children.Add((New-Text ($g.Title + '   ') $ColText 14 $true))
            [void]$info.Children.Add((New-Text ($meta -join '  -  ') $ColDim 12))
            if ($g.Description -ne '') { $d = New-Text $g.Description $ColDim 12; $d.TextWrapping = 'Wrap'; [void]$info.Children.Add($d) }
            [void]$row.Children.Add($info)
            [void]$panel.Children.Add($row)
        }
    }
    $fr = New-Object System.Windows.Controls.StackPanel; $fr.Orientation = 'Horizontal'; $fr.Margin = '0,12,0,0'
    $rb = New-Object System.Windows.Controls.Button
    $rb.Content = 'Refresh'; $rb.Padding = '10,3'; $rb.FontSize = 13
    $rb.Add_Click({ $script:libCatalog = $null; $script:libNote = ''; Render-Games })
    [void]$fr.Children.Add($rb)
    $nt = New-Text ('   ' + $script:libNote) $ColDim 12; $nt.VerticalAlignment = 'Center'
    [void]$fr.Children.Add($nt)
    [void]$panel.Children.Add($fr)

    # Putting a game online is on the Admin tab now (Publish a game).
}

# ===========================================================================
#  THE NETPLAY TAB                                               (2026-10-10)
# ===========================================================================
#  Steven's design: everything about playing online in one place, divided by
#  console, using what already exists, with plain words on how each one
#  works. The engine is scripts\NetplayEngine.ps1, which explains every
#  setting. This only draws it and wires up the buttons.
#
#  The three RetroBat settings are written STRAIGHT AWAY when changed, and
#  only while RetroBat is closed (it rewrites es_settings.cfg as it exits, so
#  a change made while it runs would be thrown away).
# ---------------------------------------------------------------------------
function New-NetCard([string]$Title, [string]$Badge, [string]$BadgeColour, [string[]]$Lines, $Buttons) {
    $card = New-Object System.Windows.Controls.Border
    $card.Background = (New-Brush $ColPanel); $card.Padding = '14,10'; $card.Margin = '0,10,0,0'
    $card.CornerRadius = '4'
    $sp = New-Object System.Windows.Controls.StackPanel
    $hd = New-Object System.Windows.Controls.StackPanel; $hd.Orientation = 'Horizontal'
    [void]$hd.Children.Add((New-Text $Title $ColText 15 $true))
    $bd = New-Object System.Windows.Controls.Border
    $bd.Background = (New-Brush $BadgeColour); $bd.CornerRadius = '3'; $bd.Padding = '6,1'; $bd.Margin = '10,2,0,0'
    $bt = New-Text $Badge '#FF111116' 11 $true
    $bd.Child = $bt
    [void]$hd.Children.Add($bd)
    [void]$sp.Children.Add($hd)
    foreach ($l in $Lines) {
        $t = New-Text $l $ColDim 13; $t.TextWrapping = 'Wrap'; $t.Margin = '0,4,0,0'
        [void]$sp.Children.Add($t)
    }
    if (@($Buttons).Count -gt 0) {
        $row = New-Object System.Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,8,0,0'
        foreach ($b in @($Buttons)) { $b.Margin = '0,0,8,0'; [void]$row.Children.Add($b) }
        [void]$sp.Children.Add($row)
    }
    $card.Child = $sp
    return $card
}

function New-NetButton([string]$Text, [scriptblock]$OnClick) {
    $b = New-Object System.Windows.Controls.Button
    $b.Content = $Text; $b.Padding = '12,4'; $b.FontSize = 13
    $b.Add_Click($OnClick)
    return $b
}

# The name others see: the profile's, when there is one.
function Get-NetplayWantedName {
    try {
        if ($script:socialOk) {
            $p = Read-SocialProfile $Ws
            if ($null -ne $p -and -not $p.Guest -and $p.Username -ne '') { return $p.Username }
        }
    } catch { }
    return ''
}

function Set-NetplayFromTab([hashtable]$Changes) {
    if (Test-RetroBatRunning) {
        [void](Show-Choice $WizardName 'RetroBat is open. Close it completely first: it rewrites its settings as it closes, and this change would be lost.' @('OK'))
        Render-Netplay
        return
    }
    $r = Set-NetplaySettings $Root $Changes
    if (-not $r.Ok) {
        Log ("netplay: could not write - {0}" -f $r.Message)
        [void](Show-Choice $WizardName "That could not be saved.`n`nDetails are in wizard.log." @('OK'))
    }
    else { Log ("netplay: {0} setting(s) changed ({1})" -f $r.Changed, (($Changes.Keys | ForEach-Object { "$_=$($Changes[$_])" }) -join ', ')) }
    Render-Netplay
}

function Open-DolphinNetplay {
    $exe = Get-DolphinExe $Root
    if ($exe -eq '') { [void](Show-Choice $WizardName 'Dolphin was not found in emulators\dolphin-emu.' @('OK')); return }
    $name = Get-NetplayWantedName
    if ($name -eq '') { try { $name = (Get-NetplaySettings $Root).Nickname } catch { } }
    try {
        [void](Set-DolphinNetplayIni $Root $name)
        Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe -Parent)
        Log 'netplay: opened Dolphin'
    }
    catch {
        Log ("netplay: could not open Dolphin - {0}" -f $_.Exception.Message)
        [void](Show-Choice $WizardName "Dolphin could not be opened.`n`nDetails are in wizard.log." @('OK'))
    }
}

function Open-NetplayProgram([string]$Exe, [string]$Label) {
    if ($Exe -eq '') { [void](Show-Choice $WizardName "$Label was not found." @('OK')); return }
    try { Start-Process -FilePath $Exe -WorkingDirectory (Split-Path $Exe -Parent); Log "netplay: opened $Label" }
    catch { Log ("netplay: could not open {0} - {1}" -f $Label, $_.Exception.Message) }
}

function Open-NetplayLink([string]$Url) {
    try { Start-Process $Url } catch { Log ("netplay: could not open {0} - {1}" -f $Url, $_.Exception.Message) }
}

function Render-Netplay {
    $panel = $script:netplayPanel
    if ($null -eq $panel) { return }
    $panel.Children.Clear()
    if (-not $script:netplayOk) {
        [void]$panel.Children.Add((New-Text 'scripts\NetplayEngine.ps1 is missing, so this tab is empty.' $ColDim 14))
        return
    }
    $intro = New-Text 'Play with friends who are not in the room. Everyone needs this wizard (the same games and the same emulators are what keep two computers in step). Lowest lag first.' $ColText 14
    $intro.TextWrapping = 'Wrap'
    [void]$panel.Children.Add($intro)

    # --- the RetroBat settings ------------------------------------------------
    $s = Get-NetplaySettings $Root
    [void]$panel.Children.Add((New-SectionHeader 'Your netplay settings'))
    if (-not $s.Ok) {
        [void]$panel.Children.Add((New-Text 'RetroBat''s settings file could not be read.' $ColDim 13))
    }
    else {
        $want = Get-NetplayWantedName
        $nameRow = New-Object System.Windows.Controls.StackPanel; $nameRow.Orientation = 'Horizontal'
        [void]$nameRow.Children.Add((New-Text ('Name friends see:  ' + $s.Nickname) $ColText 13))
        if ($want -ne '' -and $want -ne $s.Nickname) {
            $ub = New-NetButton 'Use my profile name' { Set-NetplayFromTab @{ Nickname = (Get-NetplayWantedName) } }
            $ub.Margin = '12,0,0,0'; $ub.Padding = '8,1'
            [void]$nameRow.Children.Add($ub)
        }
        elseif ($want -eq '') {
            [void]$nameRow.Children.Add((New-Text '   (make a profile on the Profile tab and this follows it)' $ColDim 12))
        }
        [void]$panel.Children.Add($nameRow)

        # private / public: two buttons, the chosen one lit
        $rt = New-Object System.Windows.Controls.StackPanel; $rt.Orientation = 'Horizontal'; $rt.Margin = '0,10,0,0'
        [void]$rt.Children.Add((New-Text 'Rooms I host:  ' $ColText 13))
        foreach ($opt in @(@('Private', $true), @('Public', $false))) {
            $b = New-Object System.Windows.Controls.Button
            $b.Content = $opt[0]; $b.Padding = '12,3'; $b.FontSize = 13; $b.Margin = '0,0,6,0'; $b.Tag = $opt[1]
            if ([bool]$opt[1] -eq $s.Private) {
                $b.Background = (New-Brush '#FF2A3A2E'); $b.BorderBrush = (New-Brush '#FF2FA84F'); $b.BorderThickness = '2'
            }
            $b.Add_Click({ param($s2, $e2) Set-NetplayFromTab @{ Private = [bool]$s2.Tag } })
            [void]$rt.Children.Add($b)
        }
        [void]$panel.Children.Add($rt)
        $pd = $(if ($s.Private) { 'Private: only people with this wizard can join your rooms, and you can join theirs.' }
                else { 'Public: anybody with the same game can join. While this is on you can join public rooms only, so switch back to Private to join a friend''s.' })
        $pt = New-Text $pd $ColDim 12; $pt.TextWrapping = 'Wrap'; $pt.Margin = '0,4,0,0'
        [void]$panel.Children.Add($pt)

        $rc = New-Object System.Windows.Controls.CheckBox
        $rc.Content = 'Friends cannot join? Use a relay server (always connects, a little more lag)'
        $rc.IsChecked = ($s.Relay -ne ''); $rc.Foreground = (New-Brush $ColText); $rc.FontSize = 13; $rc.Margin = '0,10,0,0'
        $rc.Add_Click({ param($s2, $e2) Set-NetplayFromTab @{ Relay = [bool]$s2.IsChecked } })
        [void]$panel.Children.Add($rc)
        $rt2 = New-Text 'Off is direct, the lowest lag. Turn it on when the host''s internet will not let anyone in, which happens with some routers. It only matters for whoever hosts.' $ColDim 12
        $rt2.TextWrapping = 'Wrap'; $rt2.Margin = '22,2,0,0'
        [void]$panel.Children.Add($rt2)
        if (-not $s.Enabled) {
            $eb = New-NetButton 'Turn netplay on in RetroBat' { Set-NetplayFromTab @{ Enabled = $true } }
            $eb.Margin = '0,10,0,0'; $eb.HorizontalAlignment = 'Left'
            [void]$panel.Children.Add($eb)
        }
    }

    # --- one card per console --------------------------------------------------
    [void]$panel.Children.Add((New-SectionHeader 'By console'))
    [void]$panel.Children.Add((New-NetCard 'NES, SNES and N64' 'BEST - lowest lag' $ColOnline @(
        'Built into RetroBat. Each computer runs the game and only the buttons travel, and it hides lag by quietly predicting them.',
        'Host: on the game, open its options and choose START A NETPLAY GAME, then HOST A NETPLAY GAME.',
        'Join: on the console list, open NETPLAY GAMES (its button is shown along the bottom of the screen) and pick the room.',
        'The host is player 1. N64 party games take up to 4.') @()))

    $dol = New-NetButton 'Open Dolphin for netplay' { Open-DolphinNetplay }
    [void]$panel.Children.Add((New-NetCard 'GameCube and Wii' 'GREAT' $ColOnline @(
        'Dolphin''s own netplay, in Dolphin''s own window (RetroBat cannot start it). The button fills in your name.',
        'Host: Tools > Start NetPlay > Host, pick the game, press Host, and read the code at the top out to your friends.',
        'Join: Tools > Start NetPlay > Connect, type the code, press Connect.',
        'Use controllers: real Wii Remotes do not work over netplay. If a pad does nothing, start any GameCube game from RetroBat once and quit, then try again.') @($dol)))

    $az = New-NetButton 'Open Azahar' { Open-NetplayProgram (Get-AzaharExe $Root) 'Azahar' }
    [void]$panel.Children.Add((New-NetCard '3DS' 'EXPERIMENTAL' $ColAway @(
        'Azahar links 3DS games the way local wireless did: trading Pokemon, Mario Kart 7 races.',
        'Host: Multiplayer > Host Room. Join: Multiplayer > Direct Connect, with the host''s address.',
        'The host''s router may need port 24872 opened. If it will not connect, use Parsec below.') @($az)))

    [void]$panel.Children.Add((New-NetCard 'Steam games' 'GREAT for Jackbox' $ColOnline @(
        'Steam Remote Play Together: start the game in Steam, press Shift+Tab, right-click a friend, Remote Play Together.',
        'Friends do not need to own the game. Works for games with local multiplayer. Steam setup is on the Machine tab.') @()))

    $pex = ''
    try { $pex = Get-ParsecExe } catch { }
    $pb = $(if ($pex -ne '') { New-NetButton 'Open Parsec' { Open-NetplayProgram (Get-ParsecExe) 'Parsec' } }
            else { New-NetButton 'Get Parsec (free)' { Open-NetplayLink 'https://parsec.app/downloads' } })
    [void]$panel.Children.Add((New-NetCard 'Game Boy, GBA, DS, Wii U and anything else' 'PARSEC - share a screen' $ColPlaying @(
        'One person runs the game, friends see their screen and use their own controllers. Works with any game, with a bit more lag than real netplay.',
        'Everyone installs Parsec and makes a free account. The host shares a link from Parsec; friends click it.') @($pb)))

    $pr = New-NetButton 'About Pretendo' { Open-NetplayLink 'https://pretendo.network' }
    [void]$panel.Children.Add((New-NetCard 'Wii U online' 'EXPERIMENTAL' $ColAway @(
        'Mario Kart 8, Splatoon and a few others can go online again through Pretendo, a fan-made stand-in for Nintendo''s old servers.',
        'It needs files from a real Wii U and a Pretendo account, so it is not set up on this drive yet. Parsec works today.') @($pr)))
}

# ===========================================================================
#  THE PROFILE TAB                                               (2026-10-10)
# ===========================================================================
#  Who is using this drive, their friends, and what everybody is playing.
#  The engine is scripts\SocialEngine.ps1; the background half (check-ins,
#  popups) is scripts\Social-Helper.ps1.
#
#  THE TAB NEVER WAITS ON THE NETWORK to draw. It draws from the last list
#  that arrived (social\cache\players.json) at once, and fetches a fresh one
#  in a second runspace, redrawing when it lands.
#
#  CHANGES ARE WRITTEN TO profile\profile.ini ONLY. The helper notices the
#  file change within ten seconds and sends it, so a click here never hangs
#  on GitHub. The one exception is making a profile: the name has to be
#  checked against everybody else's first, and a custom picture uploaded.
#
#  IT CAN NEVER BE THE PROBLEM. No SocialEngine.ps1, no token, no internet:
#  the tab says so in a line and everything else works as before.
# ---------------------------------------------------------------------------
$script:socialPs     = $null
$script:socialBeat   = $null
$script:noFfmpeg     = $false
$script:socialHandle = $null
$script:socialTimer  = $null
$script:socialFetched = $null
$script:socialNote   = ''
$script:socialSearch = ''
$script:AvatarIcons  = @('nes', 'snes', 'n64', 'gamecube', 'wiimote', 'gameboy', 'gba', 'ds', 'switch')
$ColOnline = '#FF2FA84F'; $ColAway = '#FFE5B83B'; $ColBusy = '#FFE0524D'; $ColPlaying = '#FF6C8CFF'

function Get-SocialDotColour([string]$Kind) {
    switch ($Kind) {
        'playing' { return $ColPlaying }
        'online'  { return $ColOnline }
        'away'    { return $ColAway }
        'busy'    { return $ColBusy }
        default   { return '#FF555560' }
    }
}

# A small picture from Windows' own icon font (Segoe MDL2 Assets, on every
# Windows 10 and 11). Codes: E70F pencil, E898 upload, E896 download, EA18
# shield. ASCII-only files cannot hold the characters, so they are built here.
function New-Glyph([string]$Code, [double]$Size, [string]$Colour = '') {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = [string][char][Convert]::ToInt32($Code, 16)
    $t.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe MDL2 Assets')
    $t.FontSize = $Size; $t.VerticalAlignment = 'Center'
    if ($Colour -ne '') { $t.Foreground = (New-Brush $Colour) }
    return $t
}

# A section header with an icon in front.
function New-IconHeader([string]$Code, [string]$Text) {
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'; $sp.Margin = '0,18,0,4'
    $g = New-Glyph $Code 16 $ColText; $g.Margin = '0,0,8,0'
    [void]$sp.Children.Add($g)
    $t = New-Text $Text $ColText 15 $true
    [void]$sp.Children.Add($t)
    return $sp
}

# The little pencil that opens an edit window.
function New-PencilButton([scriptblock]$OnClick, [string]$Tip) {
    $b = New-Object System.Windows.Controls.Button
    $b.Content = (New-Glyph 'E70F' 12 $ColDim)
    $b.Padding = '5,3'; $b.Margin = '6,0,0,0'; $b.VerticalAlignment = 'Center'; $b.Cursor = 'Hand'
    $b.Background = (New-Brush '#00000000'); $b.BorderThickness = '0'; $b.ToolTip = $Tip
    $b.Add_Click($OnClick)
    return $b
}

function New-SocialButton([string]$Text, [scriptblock]$OnClick, [string]$Tag = '') {
    $b = New-Object System.Windows.Controls.Button
    $b.Content = $Text; $b.Padding = '10,3'; $b.FontSize = 13; $b.Margin = '6,0,0,0'
    $b.VerticalAlignment = 'Center'; $b.Tag = $Tag
    $b.Add_Click($OnClick)
    return $b
}

# A person's picture: a pixel icon from wizard\profile-<name>.png, or their
# own picture (this drive's own from profile\avatar.png, a friend's from the
# cache). Nothing at all when neither can be found.
function New-SocialAvatar($Player, [int]$Size, [bool]$Mine = $false) {
    $img = New-Object System.Windows.Controls.Image
    $img.Width = $Size; $img.Height = $Size; $img.Margin = '0,0,10,0'; $img.VerticalAlignment = 'Center'
    try {
        $path = ''
        $av = [string]$Player.Avatar
        if ($av -like 'custom:*') {
            if ($Mine) { $path = (Get-SocialPaths $Ws).Avatar }
            else {
                $P = Get-SocialPaths $Ws
                $tagPart = $av.Substring(7)
                $path = Join-SocialPath (Join-SocialPath $P.Cache 'avatars') ($Player.Id + '-' + $tagPart + '.png')
            }
        }
        else {
            $path = Join-Path $WizardDir ('profile-' + ($av -replace '^icon:', '') + '.png')
            [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, [System.Windows.Media.BitmapScalingMode]::NearestNeighbor)
        }
        $bmp = Get-PixelBitmap $path
        if ($null -ne $bmp) { $img.Source = $bmp }
    } catch { }
    return $img
}

function Get-SocialPlayersNow {
    if ($null -ne $script:socialFetched) { return @($script:socialFetched) }
    try { return @(Get-SocialCachedPlayers $Ws) } catch { return @() }
}

# --- the background fetch ---------------------------------------------------
function Start-SocialFetch {
    if (-not $script:socialOk) { return }
    if ($null -ne $script:socialHandle) { return }
    $prof = $null
    try { $prof = Read-SocialProfile $Ws } catch { }
    if ($null -eq $prof -or $prof.Guest) { return }
    try {
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        try { $iss.ExecutionPolicy = 'Bypass' } catch { }
        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
        $rs.Open()
        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $rs
        # Custom pictures are fetched here too, once per change, so the list
        # can show them from the cache without waiting.
        [void]$ps.AddScript('param($lib, $ws) . $lib; $r = Get-SocialPlayers $ws; if ($r.Ok) { foreach ($p in @($r.Players)) { if ($p.Avatar -like ''custom:*'') { [void](Get-SocialAvatarFile $ws $p) } }; ''ok'' } else { $r.Message }')
        [void]$ps.AddArgument($script:socialLib)
        [void]$ps.AddArgument($Ws)
        $script:socialPs = $ps
        $script:socialHandle = $ps.BeginInvoke()
        $script:socialTicks = 0
        if ($null -eq $script:socialTimer) {
            $script:socialTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:socialTimer.Interval = [TimeSpan]::FromMilliseconds(600)
            $script:socialTimer.Add_Tick({ Invoke-SocialFetchTick })
        }
        $script:socialTimer.Start()
    }
    catch {
        Log ("profile: could not start a fetch - {0}" -f $_.Exception.Message)
        $script:socialHandle = $null
    }
}

function Invoke-SocialFetchTick {
    try {
        $script:socialTicks++
        if ($null -eq $script:socialHandle) { $script:socialTimer.Stop(); return }
        if (-not $script:socialHandle.IsCompleted) {
            if ($script:socialTicks -gt 100) { $script:socialTimer.Stop(); $script:socialNote = 'No answer from GitHub.'; $script:socialHandle = $null; Render-Social }
            return
        }
        $script:socialTimer.Stop()
        $out = ''
        try { $out = [string](@($script:socialPs.EndInvoke($script:socialHandle)) -join '') } catch { $out = $_.Exception.Message }
        try { $script:socialPs.Runspace.Dispose(); $script:socialPs.Dispose() } catch { }
        $script:socialPs = $null; $script:socialHandle = $null
        if ($out -eq 'ok') {
            $script:socialFetched = @(Get-SocialCachedPlayers $Ws)
            $script:socialNote = 'Updated ' + (Get-Date -Format 'h:mm tt') + '.'
            $ex = Get-SocialCachedExtras $Ws
            $n = ''
            try { $n = Update-SocialFromOnline $Ws $script:socialFetched $ex } catch { Log "profile: online sync - $_" }
            if ($n -ne '') { $script:socialNote = $n; Log ("profile: " + $n) }
            Sync-AdminTab $ex
        }
        else { $script:socialNote = $(if ($out) { $out } else { 'Could not reach GitHub.' }) + ' Showing the last list.' }
        Render-Social
    }
    catch { Log ("profile tick: {0}" -f $_.Exception.Message) }
}

# When the window opens: start the helper (only one ever runs), keep it told
# that the wizard is open, fetch now and every two minutes.
function Start-SocialSession {
    if (-not $script:socialOk) { return }
    $prof = $null
    try { $prof = Read-SocialProfile $Ws } catch { }
    if ($null -eq $prof -or $prof.Guest) { return }
    Start-SocialHelper
    Start-SocialFetch
    if ($null -ne $script:socialBeat) { return }   # already ticking (first-run setup started it)
    try {
        $script:socialBeat = New-Object System.Windows.Threading.DispatcherTimer
        $script:socialBeat.Interval = [TimeSpan]::FromSeconds(60)
        $script:socialBeatCount = 0
        $script:socialBeat.Add_Tick({
            try {
                Set-SocialAlive
                $script:socialBeatCount++
                if ($script:socialBeatCount % 2 -eq 0) { Start-SocialFetch }
            } catch { }
        })
        $script:socialBeat.Start()
    } catch { }
}

function Set-SocialAlive {
    try {
        $P = Get-SocialPaths $Ws
        New-SocialDir $P.SocialDir
        [System.IO.File]::WriteAllText((Join-Path $P.SocialDir 'wizard-alive.txt'), (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    } catch { }
}

function Start-SocialHelper {
    try {
        Set-SocialAlive
        $helper = Join-Path $ScriptsDir 'Social-Helper.ps1'
        if (-not (Test-Path -LiteralPath $helper)) { return }
        $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $argLine = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $helper
        Start-Process -FilePath $ps -ArgumentList $argLine -WindowStyle Hidden
        Log 'profile: helper started (it exits at once if one is already running)'
    }
    catch { Log ("profile: could not start the helper - {0}" -f $_.Exception.Message) }
}

# --- saving a change ----------------------------------------------------------
function Save-SocialProfile($Prof) {
    try { Write-SocialProfile $Ws $Prof; return $true }
    catch {
        Log ("profile: could not write profile.ini - {0}" -f $_.Exception.Message)
        [void](Show-Choice $WizardName "Your profile could not be saved.`n`nDetails are in wizard.log." @('OK'))
        return $false
    }
}

# --- drawing the tab -----------------------------------------------------------
function Render-Social {
    $panel = $script:socialPanel
    if ($null -eq $panel) { return }
    $panel.Children.Clear()

    if (-not $script:socialOk) {
        [void]$panel.Children.Add((New-Text 'scripts\SocialEngine.ps1 is missing, so there is no Profile tab on this drive.' $ColDim 14))
        return
    }
    $prof = $null
    try { $prof = Read-SocialProfile $Ws } catch { Log "profile: $_" }

    # --- nobody logged in: the login screen ------------------------------------
    if ($null -eq $prof -or $prof.Guest) {
        Render-SocialLogin $panel $prof
        return
    }

    $token = Get-SocialToken $Ws
    $now = Get-SocialNowUtc
    $players = @(Get-SocialPlayersNow)

    # --- you -------------------------------------------------------------------
    [void]$panel.Children.Add((New-SectionHeader 'You'))
    $me = New-Object System.Windows.Controls.DockPanel; $me.Margin = '0,4,0,0'
    $avBox = New-Object System.Windows.Controls.StackPanel; $avBox.Orientation = 'Horizontal'
    [void]$avBox.Children.Add((New-SocialAvatar $prof 48 $true))
    $pp = New-PencilButton { Invoke-SocialPicture } 'Change your picture'
    $pp.Margin = '-14,30,8,0'
    [void]$avBox.Children.Add($pp)
    [System.Windows.Controls.DockPanel]::SetDock($avBox, 'Left')
    [void]$me.Children.Add($avBox)
    $mid = New-Object System.Windows.Controls.StackPanel; $mid.VerticalAlignment = 'Center'
    # The dot tells the truth, like Discord: it is grey unless this drive's
    # check-in really reached GitHub lately, whatever status was picked.
    $self = Get-SocialSelfPresence $prof $players $now ($token -ne '')
    $nr = New-Object System.Windows.Controls.StackPanel; $nr.Orientation = 'Horizontal'
    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = 11; $dot.Height = 11; $dot.Margin = '0,0,7,0'; $dot.VerticalAlignment = 'Center'
    $dot.Fill = (New-Brush (Get-SocialDotColour $self.Kind))
    [void]$nr.Children.Add($dot)
    [void]$nr.Children.Add((New-Text $prof.Username $ColText 17 $true))
    [void]$nr.Children.Add((New-PencilButton { Invoke-SocialNameRequest } 'Ask for a new name'))
    [void]$mid.Children.Add($nr)
    [void]$mid.Children.Add((New-Text $self.Line $ColDim 13))
    if ($prof.NameReq -ne '') {
        $rq = New-Object System.Windows.Controls.StackPanel; $rq.Orientation = 'Horizontal'; $rq.Margin = '0,4,0,0'
        [void]$rq.Children.Add((New-Text ("New name '{0}' is waiting for an admin to approve it." -f $prof.NameReq) $ColAway 12))
        $cx = New-SocialButton 'Cancel request' { $p = Read-SocialProfile $Ws; $p.NameReq = ''; [void](Save-SocialProfile $p); Render-Social }
        $cx.FontSize = 11; $cx.Padding = '6,1'
        [void]$rq.Children.Add($cx)
        [void]$mid.Children.Add($rq)
    }
    [void]$me.Children.Add($mid)
    [void]$panel.Children.Add($me)
    if ($prof.Pw -eq '') {
        $pw = New-Text 'No password yet. Set one so nobody else can log in as you, and so you can log in on other drives.' $ColAway 12
        $pw.Margin = '0,8,0,0'
        [void]$panel.Children.Add($pw)
    }

    # status + custom text
    $sr = New-Object System.Windows.Controls.StackPanel; $sr.Orientation = 'Horizontal'; $sr.Margin = '0,10,0,0'
    [void]$sr.Children.Add((New-Text 'Status' $ColDim 13))
    $cb = New-Object System.Windows.Controls.ComboBox
    $cb.Width = 120; $cb.Margin = '10,0,0,0'; $cb.FontSize = 13
    foreach ($s in @('Online', 'Away', 'Busy', 'Invisible')) { [void]$cb.Items.Add($s) }
    $script:socialStatusLoading = $true
    $cb.SelectedItem = (Get-Culture).TextInfo.ToTitleCase($prof.Status)
    $script:socialStatusLoading = $false
    $cb.Add_SelectionChanged({
        param($s2, $e2)
        if ($script:socialStatusLoading) { return }
        $p = Read-SocialProfile $Ws
        $p.Status = ([string]$s2.SelectedItem).ToLower()
        if (Save-SocialProfile $p) { Log ("profile: status {0}" -f $p.Status) }
        Render-Social
    })
    [void]$sr.Children.Add($cb)
    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Width = 220; $tb.Margin = '14,0,0,0'; $tb.FontSize = 13; $tb.Padding = '4,2'; $tb.MaxLength = 40
    $tb.Text = $prof.Text; $tb.ToolTip = 'A short line under your name, like "down for Smash"'
    $script:socialTextBox = $tb
    [void]$sr.Children.Add($tb)
    [void]$sr.Children.Add((New-SocialButton 'Set' {
        $p = Read-SocialProfile $Ws
        $p.Text = Get-SocialClean ([string]$script:socialTextBox.Text) 40
        [void](Save-SocialProfile $p); Render-Social
    }))
    [void]$panel.Children.Add($sr)

    # toggles
    $tg = New-Object System.Windows.Controls.StackPanel; $tg.Orientation = 'Horizontal'; $tg.Margin = '0,8,0,0'
    $c1 = New-Object System.Windows.Controls.CheckBox
    $c1.Content = 'Show what I am playing'; $c1.IsChecked = $prof.ShowGame; $c1.Foreground = (New-Brush $ColText); $c1.FontSize = 13
    $c1.Add_Click({ param($s2, $e2) $p = Read-SocialProfile $Ws; $p.ShowGame = [bool]$s2.IsChecked; [void](Save-SocialProfile $p) })
    $c2 = New-Object System.Windows.Controls.CheckBox
    $c2.Content = 'Popups when friends come online'; $c2.IsChecked = $prof.Popups; $c2.Foreground = (New-Brush $ColText); $c2.FontSize = 13
    $c2.Margin = '18,0,0,0'
    $c2.Add_Click({ param($s2, $e2) $p = Read-SocialProfile $Ws; $p.Popups = [bool]$s2.IsChecked; [void](Save-SocialProfile $p) })
    [void]$tg.Children.Add($c1); [void]$tg.Children.Add($c2)
    [void]$panel.Children.Add($tg)

    if ($token -eq '') {
        $w = New-Text 'This drive has no key for the friends list (social\social-token.txt), so nothing can be sent or read.' '#FFE5B83B' 13
        $w.TextWrapping = 'Wrap'; $w.Margin = '0,10,0,0'
        [void]$panel.Children.Add($w)
    }

    $view = $null
    try { $view = Get-SocialView $prof $players $now } catch { Log "profile view: $_" }
    if ($null -eq $view) { $view = [pscustomobject]@{ Friends = @(); Incoming = @(); Outgoing = @() } }

    # --- requests ------------------------------------------------------------
    if (@($view.Incoming).Count -gt 0) {
        [void]$panel.Children.Add((New-SectionHeader 'Friend requests'))
        foreach ($p in @($view.Incoming)) {
            $row = New-SocialPersonRow $p $now
            [void]$row.Children.Add((New-SocialButton 'Accept' { param($s2, $e2) Invoke-SocialAction 'accept' ([string]$s2.Tag) } $p.Id))
            [void]$row.Children.Add((New-SocialButton 'Decline' { param($s2, $e2) Invoke-SocialAction 'decline' ([string]$s2.Tag) } $p.Id))
            [void]$panel.Children.Add($row)
        }
    }

    # --- friends -------------------------------------------------------------
    [void]$panel.Children.Add((New-SectionHeader ('Friends ({0} online)' -f @($view.Friends | Where-Object { (Get-SocialPresence $_ $now).Kind -ne 'offline' }).Count)))
    if (@($view.Friends).Count -eq 0) {
        [void]$panel.Children.Add((New-Text 'No friends yet. Find somebody by name below.' $ColDim 13))
    }
    foreach ($p in @($view.Friends)) {
        $row = New-SocialPersonRow $p $now
        $rm = New-SocialButton 'Remove' { param($s2, $e2) Invoke-SocialAction 'remove' ([string]$s2.Tag) } $p.Id
        $rm.FontSize = 11; $rm.Padding = '6,1'
        [void]$row.Children.Add($rm)
        [void]$panel.Children.Add($row)
    }

    if (@($view.Outgoing).Count -gt 0) {
        [void]$panel.Children.Add((New-SectionHeader 'Waiting for them to accept'))
        foreach ($p in @($view.Outgoing)) {
            $row = New-SocialPersonRow $p $now
            [void]$row.Children.Add((New-SocialButton 'Cancel' { param($s2, $e2) Invoke-SocialAction 'cancel' ([string]$s2.Tag) } $p.Id))
            [void]$panel.Children.Add($row)
        }
    }

    # --- add a friend --------------------------------------------------------
    [void]$panel.Children.Add((New-SectionHeader 'Add a friend'))
    $fr = New-Object System.Windows.Controls.StackPanel; $fr.Orientation = 'Horizontal'
    $q = New-Object System.Windows.Controls.TextBox
    $q.Width = 220; $q.FontSize = 13; $q.Padding = '4,2'; $q.Text = $script:socialSearch
    $script:socialSearchBox = $q
    $q.Add_KeyDown({ param($s2, $e2) if ($e2.Key -eq 'Return') { $script:socialSearch = [string]$script:socialSearchBox.Text; Render-Social } })
    [void]$fr.Children.Add($q)
    [void]$fr.Children.Add((New-SocialButton 'Search' { $script:socialSearch = [string]$script:socialSearchBox.Text; Render-Social }))
    [void]$panel.Children.Add($fr)
    if ($script:socialSearch.Trim() -ne '') {
        $hits = @(Find-SocialPlayers $prof $players $script:socialSearch)
        if ($hits.Count -eq 0) { [void]$panel.Children.Add((New-Text 'Nobody by that name. Names come from the last list that arrived; Refresh fetches a new one.' $ColDim 13)) }
        foreach ($p in $hits) {
            $row = New-SocialPersonRow $p $now
            $fIds = @($view.Friends | ForEach-Object { $_.Id }); $oIds = @($view.Outgoing | ForEach-Object { $_.Id }); $iIds = @($view.Incoming | ForEach-Object { $_.Id })
            if     ($fIds -contains $p.Id) { [void]$row.Children.Add((New-Text '   Friends' $ColDim 12)) }
            elseif ($oIds -contains $p.Id) { [void]$row.Children.Add((New-Text '   Request sent' $ColDim 12)) }
            elseif ($iIds -contains $p.Id) { [void]$row.Children.Add((New-SocialButton 'Accept' { param($s2, $e2) Invoke-SocialAction 'accept' ([string]$s2.Tag) } $p.Id)) }
            else { [void]$row.Children.Add((New-SocialButton 'Add friend' { param($s2, $e2) Invoke-SocialAction 'add' ([string]$s2.Tag) } $p.Id)) }
            [void]$panel.Children.Add($row)
        }
    }

    # --- footer ----------------------------------------------------------------
    $ft = New-Object System.Windows.Controls.StackPanel; $ft.Orientation = 'Horizontal'; $ft.Margin = '0,18,0,0'
    $rf = New-SocialButton 'Refresh' { $script:socialNote = 'Checking...'; Render-Social; Start-SocialFetch }
    $rf.Margin = '0'
    [void]$ft.Children.Add($rf)
    [void]$ft.Children.Add((New-SocialButton $(if ($prof.Pw -eq '') { 'Set a password' } else { 'Change password' }) { Invoke-SocialPassword }))
    [void]$ft.Children.Add((New-SocialButton 'Log out' { Invoke-SocialLogout }))
    $nt = New-Text ('  ' + $script:socialNote) $ColDim 12; $nt.VerticalAlignment = 'Center'
    [void]$ft.Children.Add($nt)
    [void]$panel.Children.Add($ft)
    Add-SocialDisclaimer $panel
}

function Add-SocialDisclaimer($panel) {
    $d = New-Text 'A side project with no real online protection. Shared with other people who use this wizard: your name, picture, status, friends list and what you are playing. Nothing else leaves the drive.' '#FF777780' 11
    $d.TextWrapping = 'Wrap'; $d.Margin = '0,14,0,0'; $d.MaxWidth = 600; $d.HorizontalAlignment = 'Left'
    [void]$panel.Children.Add($d)
}

# One line in a list: picture, name, a coloured dot and what they are up to.
function New-SocialPersonRow($Player, [DateTime]$NowUtc, [bool]$NoPresence = $false) {
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.Margin = '0,8,0,0'
    [void]$row.Children.Add((New-SocialAvatar $Player 32))
    $txt = New-Object System.Windows.Controls.StackPanel; $txt.VerticalAlignment = 'Center'; $txt.Width = 330
    $nameRow = New-Object System.Windows.Controls.StackPanel; $nameRow.Orientation = 'Horizontal'
    $pr = Get-SocialPresence $Player $NowUtc
    if (-not $NoPresence) {
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = 9; $dot.Height = 9; $dot.Margin = '0,0,6,0'; $dot.VerticalAlignment = 'Center'
        $dot.Fill = (New-Brush (Get-SocialDotColour $pr.Kind))
        [void]$nameRow.Children.Add($dot)
    }
    [void]$nameRow.Children.Add((New-Text $Player.Username $ColText 14 $true))
    [void]$txt.Children.Add($nameRow)
    if (-not $NoPresence) {
        $l = New-Text $pr.Line $ColDim 12; $l.TextTrimming = 'CharacterEllipsis'
        [void]$txt.Children.Add($l)
    }
    [void]$row.Children.Add($txt)
    return $row
}

# --- actions --------------------------------------------------------------------
function Invoke-SocialAction([string]$What, [string]$Id) {
    $p = Read-SocialProfile $Ws
    if ($null -eq $p -or $p.Guest) { return }
    $name = $Id
    foreach ($x in @(Get-SocialPlayersNow)) { if ($x.Id -eq $Id) { $name = $x.Username } }
    switch ($What) {
        'add'     { Add-SocialFriend $p $Id }
        'accept'  { Add-SocialFriend $p $Id }
        'decline' { Deny-SocialRequest $p $Id }
        'cancel'  { Remove-SocialFriend $p $Id }
        'remove'  {
            $pick = Show-Choice $WizardName ("Remove $name from your friends?`n`nThey are not told. Either of you can send a new request later.") @('Remove', 'Keep')
            if ($pick -ne 'Remove') { return }
            Remove-SocialFriend $p $Id
        }
    }
    if (Save-SocialProfile $p) {
        Log ("profile: {0} {1}" -f $What, $name)
        $script:socialNote = 'Saved. Your friends see it within a minute or two.'
    }
    Render-Social
}

# No profile yet and the person picked guest (first run). Logged-in people
# log out instead (Invoke-SocialLogout).
function Invoke-SocialGuest {
    $p = $null
    try { $p = Read-SocialProfile $Ws } catch { }
    if ($null -ne $p -and -not $p.Guest) { Invoke-SocialLogout; return }
    if (Save-SocialProfile ([pscustomobject]@{ Guest = $true })) { Log 'profile: guest' }
    Render-Social
}

# Signs off (one last "offline" check-in), remembers the profile on this
# drive's login screen, and goes back to that screen. The profile itself
# lives online, so logging back in (here or on any drive) picks it all up.
function Invoke-SocialLogout {
    $p = Read-SocialProfile $Ws
    if ($null -eq $p -or $p.Guest) { return }
    $msg = "Log out?`n`nYou go offline and this drive goes back to the login screen. Your profile stays online, so you can log back in here or on any drive with the wizard."
    if ($p.Pw -eq '') { $msg += "`n`nYou have no password yet, so anybody could log in as you. Set one first if that matters." }
    if ((Show-Choice $WizardName $msg @('Log out', 'Cancel')) -ne 'Log out') { return }
    try {
        $gone = [pscustomobject]@{ State = 'offline'; InGame = $false; Game = ''; Console = ''; Since = '' }
        [void](Publish-SocialRecord $Ws $p $gone $WizardVersion)
    } catch { Log "profile: logout check-in - $_" }
    try { Add-SocialLogin $Ws $p } catch { Log "profile: could not remember the login - $_" }
    if (Save-SocialProfile ([pscustomobject]@{ Guest = $true })) { Log ("profile: logged out {0}" -f $p.Username) }
    $script:socialNote = ''
    Sync-AdminTab
    Render-Social
}

# What this drive's own dot shows. Kind and Line, like Get-SocialPresence,
# but measured: grey unless this drive's own file online was written lately.
function Get-SocialSelfPresence($Prof, $Players, [DateTime]$NowUtc, [bool]$HasKey) {
    $mine = @($Players | Where-Object { $null -ne $_ -and $_.Id -eq $Prof.Id }) | Select-Object -First 1
    $live = $HasKey -and $null -ne $mine -and $null -ne $mine.Seen -and $mine.State -ne 'offline' -and
            (($NowUtc - $mine.Seen).TotalMinutes -le $script:SocialOnlineMinutes)
    $extra = $(if ($Prof.Text -ne '') { ' - ' + $Prof.Text } else { '' })
    if ($Prof.Status -eq 'invisible') { return [pscustomobject]@{ Kind = 'offline'; Line = 'Invisible: friends see you as offline' } }
    if (-not $live) {
        $why = $(if (-not $HasKey) { 'no key on this drive' } else { 'not connected yet (no internet, or it is still starting)' })
        return [pscustomobject]@{ Kind = 'offline'; Line = "Offline - $why" }
    }
    if ($mine.InGame) { return [pscustomobject]@{ Kind = 'playing'; Line = (Get-SocialPresence $mine $NowUtc).Line } }
    $word = @{ online = 'Online'; away = 'Away'; busy = 'Busy' }[$Prof.Status]
    return [pscustomobject]@{ Kind = $Prof.Status; Line = ($word + $extra) }
}

# --- the login screen -----------------------------------------------------------
$script:loginHits = $null
$script:loginNote = ''
function Render-SocialLogin($panel, $prof) {
    [void]$panel.Children.Add((New-SectionHeader 'Who is playing?'))
    $intro = 'Log in to see your friends, or make a profile. Profiles live online, so yours works on any drive with the wizard.'
    if ($null -ne $prof -and $prof.Guest) { $intro = 'Nobody is logged in, so nothing about you is sent anywhere. ' + $intro }
    $t = New-Text $intro $ColText 14; $t.Margin = '0,0,0,6'
    [void]$panel.Children.Add($t)

    $logins = @(Get-SocialLogins $Ws)
    if ($logins.Count -gt 0) {
        [void]$panel.Children.Add((New-SectionHeader 'Log back in'))
        foreach ($l in $logins) {
            $row = New-Object System.Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,6,0,0'
            [void]$row.Children.Add((New-SocialAvatar $l 32))
            $nm = New-Text $l.Username $ColText 14 $true; $nm.Width = 200; $nm.VerticalAlignment = 'Center'
            [void]$row.Children.Add($nm)
            [void]$row.Children.Add((New-SocialButton 'Log in' { param($s2, $e2) Invoke-SocialLogin ([string]$s2.Tag) } $l.Id))
            $x = New-SocialButton 'Forget' { param($s2, $e2) Remove-SocialLogin $Ws ([string]$s2.Tag); Render-Social } $l.Id
            $x.FontSize = 11; $x.Padding = '6,1'; $x.ToolTip = 'Take it off this list (the profile itself stays)'
            [void]$row.Children.Add($x)
            [void]$panel.Children.Add($row)
        }
    }

    [void]$panel.Children.Add((New-SectionHeader 'Log in to another profile'))
    $fr = New-Object System.Windows.Controls.StackPanel; $fr.Orientation = 'Horizontal'
    $q = New-Object System.Windows.Controls.TextBox
    $q.Width = 220; $q.FontSize = 13; $q.Padding = '4,2'; $q.Text = $script:socialSearch
    $script:socialSearchBox = $q
    $q.Add_KeyDown({ param($s2, $e2) if ($e2.Key -eq 'Return') { Invoke-SocialLoginSearch } })
    [void]$fr.Children.Add($q)
    [void]$fr.Children.Add((New-SocialButton 'Search' { Invoke-SocialLoginSearch }))
    [void]$panel.Children.Add($fr)
    if ($script:loginNote -ne '') { $ln = New-Text $script:loginNote $ColDim 12; $ln.Margin = '0,4,0,0'; [void]$panel.Children.Add($ln) }
    foreach ($p in @($script:loginHits)) {
        if ($null -eq $p) { continue }
        $row = New-Object System.Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,6,0,0'
        [void]$row.Children.Add((New-SocialAvatar $p 32))
        $nm = New-Text $p.Username $ColText 14 $true; $nm.Width = 200; $nm.VerticalAlignment = 'Center'
        [void]$row.Children.Add($nm)
        [void]$row.Children.Add((New-SocialButton 'Log in' { param($s2, $e2) Invoke-SocialLogin ([string]$s2.Tag) } $p.Id))
        [void]$panel.Children.Add($row)
    }

    [void]$panel.Children.Add((New-SectionHeader 'New here?'))
    $row2 = New-Object System.Windows.Controls.StackPanel; $row2.Orientation = 'Horizontal'
    $mk = New-SocialButton 'Make my profile' { Invoke-SocialCreate }
    $mk.Margin = '0'; $mk.FontWeight = 'Bold'; $mk.Padding = '14,6'; $mk.FontSize = 14
    [void]$row2.Children.Add($mk)
    if ($null -eq $prof) {
        $gb = New-SocialButton 'Continue as guest' { Invoke-SocialGuest }
        $gb.Margin = '8,0,0,0'; $gb.Padding = '14,6'; $gb.FontSize = 14
        [void]$row2.Children.Add($gb)
    }
    [void]$panel.Children.Add($row2)
    Add-SocialDisclaimer $panel
}

# Logged out, the background fetch is off, so a search asks GitHub itself.
function Invoke-SocialLoginSearch {
    $script:socialSearch = [string]$script:socialSearchBox.Text
    $script:loginHits = @(); $script:loginNote = ''
    if ($script:socialSearch.Trim() -eq '') { Render-Social; return }
    $all = Get-SocialPlayers $Ws
    $list = $(if ($all.Ok) { @($all.Players) } else { @(Get-SocialCachedPlayers $Ws) })
    if (-not $all.Ok) { $script:loginNote = 'Could not reach GitHub; searched the last list this drive saw.' }
    $script:loginHits = @(Find-SocialPlayers ([pscustomobject]@{ Id = '' }) $list $script:socialSearch)
    if ($script:loginHits.Count -eq 0 -and $script:loginNote -eq '') { $script:loginNote = 'Nobody by that name.' }
    Render-Social
}

function Invoke-SocialLogin([string]$Id) {
    $all = Get-SocialPlayers $Ws
    if (-not $all.Ok) { [void](Show-Choice $WizardName "Logging in needs the internet, and GitHub could not be reached.`n`n$($all.Message)" @('OK')); return }
    $rec = @($all.Players | Where-Object { $null -ne $_ -and $_.Id -eq $Id }) | Select-Object -First 1
    if ($null -eq $rec) { [void](Show-Choice $WizardName 'That profile is not online any more.' @('OK')); return }
    if ($rec.Pw -ne '') {
        $pw = Show-PasswordDialog 'Log in' ("Password for {0}:" -f $rec.Username) $false
        if ($null -eq $pw) { return }
        if (-not (Test-SocialPassword $rec $pw)) { [void](Show-Choice $WizardName 'That password is not right.' @('OK')); return }
    }
    $prof = New-SocialProfileFromRecord $rec
    if ($rec.Avatar -like 'custom:*') {
        $f = Get-SocialAvatarFile $Ws $rec
        $P = Get-SocialPaths $Ws
        if ($f -ne '') { New-SocialDir $P.ProfileDir; Copy-Item -LiteralPath $f -Destination $P.Avatar -Force }
        else { $prof.Avatar = 'icon:gameboy' }
    }
    if (-not (Save-SocialProfile $prof)) { return }
    try { Add-SocialLogin $Ws $prof } catch { }
    Log ("profile: logged in as {0} ({1})" -f $prof.Username, $prof.Id)
    $script:socialFetched = @($all.Players)
    $script:loginHits = $null; $script:socialSearch = ''; $script:loginNote = ''
    $script:socialNote = "Welcome back, $($prof.Username)!"
    Start-SocialSession
    Sync-AdminTab
    Render-Social
}

# Making a profile: a name, a picture, a check that nobody has the name, and
# a password (skippable; the tab keeps asking for one).
function Invoke-SocialCreate {
    $ed = Show-SocialEditor 'Make my profile' '' 'icon:gameboy'
    if (-not $ed.Ok) { Render-Social; return }
    if (-not (Test-SocialNameFree $ed.Name '')) { Render-Social; return }
    $prof = New-SocialProfile $ed.Name $ed.Avatar
    Complete-SocialPicture $prof $ed
    $pw = Show-PasswordDialog 'Pick a password' "A password lets you log in on other drives and stops friends logging in as you.`n`nIt is a light lock: do not use a password you use anywhere else." $true
    if ($null -ne $pw) { $prof.Pw = Get-SocialPasswordHash $prof.Id $pw; $prof.PwSet = Format-SocialTime (Get-SocialNowUtc) }
    if (Save-SocialProfile $prof) {
        try { Add-SocialLogin $Ws $prof } catch { }
        Log ("profile: made '{0}' ({1})" -f $prof.Username, $prof.Id)
        $script:socialNote = 'Welcome! Find friends by name below.'
        Start-SocialSession
    }
    Render-Social
}

function Invoke-SocialPicture {
    $prof = Read-SocialProfile $Ws
    if ($null -eq $prof -or $prof.Guest) { return }
    $ed = Show-SocialEditor 'Change picture' $prof.Username $prof.Avatar $true
    if (-not $ed.Ok) { return }
    $prof.Avatar = $ed.Avatar
    Complete-SocialPicture $prof $ed
    [void](Save-SocialProfile $prof)
    try { Add-SocialLogin $Ws $prof } catch { }
    Render-Social
}

# A new name is a request: an admin approves it, then this drive's wizard
# (or its helper) changes the name when it sees the answer.
function Invoke-SocialNameRequest {
    $prof = Read-SocialProfile $Ws
    if ($null -eq $prof -or $prof.Guest) { return }
    $new = (Show-TextInput $WizardName "Ask for a new name.`n`nAn admin approves it, then it changes everywhere. 3 to 20 letters, numbers, spaces, dots and dashes." $prof.Username).Trim()
    if ($new -eq '' -or $new -eq $prof.Username) { return }
    if (-not (Test-SocialNameFree $new $prof.Id)) { return }
    $prof.NameReq = $new
    if (Save-SocialProfile $prof) {
        Log ("profile: asked for the name {0}" -f $new)
        $script:socialNote = 'Request sent. Your name changes once an admin approves it.'
        [void](Send-SocialNotify $Ws 'Name request' ("{0} wants to be called {1}" -f $prof.Username, $new))
    }
    Render-Social
}

function Invoke-SocialPassword {
    $prof = Read-SocialProfile $Ws
    if ($null -eq $prof -or $prof.Guest) { return }
    $pw = Show-PasswordDialog 'Password' "A light lock: it stops friends logging in as you, and lets you log in on other drives.`n`nDo not use a password you use anywhere else." $true
    if ($null -eq $pw) { return }
    $prof.Pw = Get-SocialPasswordHash $prof.Id $pw
    $prof.PwSet = Format-SocialTime (Get-SocialNowUtc)
    if (Save-SocialProfile $prof) { $script:socialNote = 'Password saved.'; Log 'profile: password set' }
    Render-Social
}

# Returns the password, or $null when cancelled. $Confirm asks twice and
# wants at least 4 letters.
function Show-PasswordDialog([string]$Title, [string]$Message, [bool]$Confirm) {
    Close-Splash
    $w = New-Object System.Windows.Window
    $w.Title = $Title; $w.Width = 440; $w.SizeToContent = 'Height'
    $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'NoResize'
    $w.Background = (New-Brush $ColBg); $w.Topmost = $true
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '22'
    $m = New-Text $Message $ColText 14; $m.Margin = '0,0,0,12'
    [void]$sp.Children.Add($m)
    $b1 = New-Object System.Windows.Controls.PasswordBox; $b1.FontSize = 15; $b1.Padding = '6,4'
    [void]$sp.Children.Add($b1)
    $b2 = New-Object System.Windows.Controls.PasswordBox; $b2.FontSize = 15; $b2.Padding = '6,4'; $b2.Margin = '0,8,0,0'
    if ($Confirm) { [void]$sp.Children.Add((New-Text 'Once more:' $ColDim 12)); [void]$sp.Children.Add($b2) }
    $err = New-Text '' $ColAway 12; $err.Margin = '0,6,0,0'
    [void]$sp.Children.Add($err)
    $script:pwWin = $w; $script:pwB1 = $b1; $script:pwB2 = $b2; $script:pwErr = $err; $script:pwConfirm = $Confirm; $script:pwResult = $null
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.HorizontalAlignment = 'Right'; $row.Margin = '0,14,0,0'
    foreach ($label in @('Cancel', 'OK')) {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $label; $b.Tag = $label; $b.Margin = '8,0,0,0'; $b.Padding = '16,7'; $b.FontSize = 14
        if ($label -eq 'OK') { $b.IsDefault = $true }
        $b.Add_Click({
            param($s2, $e2)
            if ([string]$s2.Tag -eq 'OK') {
                $a = [string]$script:pwB1.Password
                if ($script:pwConfirm) {
                    if ($a.Length -lt 4) { $script:pwErr.Text = 'At least 4 letters.'; return }
                    if ($a -ne [string]$script:pwB2.Password) { $script:pwErr.Text = 'The two do not match.'; return }
                }
                $script:pwResult = $a
            }
            $script:pwWin.Close()
        })
        [void]$row.Children.Add($b)
    }
    [void]$sp.Children.Add($row)
    $w.Content = $sp
    $w.Add_ContentRendered({ $script:pwB1.Focus() })
    [void]$w.ShowDialog()
    return $script:pwResult
}

# ===========================================================================
#  ADMIN TAB                                                     (2026-10-10)
# ===========================================================================
#  Steven: "add an admin role that unlocks extra things so I can review
#  people's reports, and potentially in the future let someone else be an
#  admin too." The tab is added after Help only for a person on the admins
#  list (admin\admins.txt in the private repo), and taken away again when
#  they come off it. Nothing else in the wizard changes for an admin.
#  It loads nothing until it is used: GitHub is asked when Refresh is pressed.
# ---------------------------------------------------------------------------
$script:adminTab = $null
$script:adminReports = $null
$script:adminTopic = $null
$script:adminNote = ''
$script:adminLibJob = $null

function Sync-AdminTab($Extras = $null) {
    try {
        if (-not $script:adminOk -or $null -eq $script:tabs) { return }
        if ($null -eq $Extras) { $Extras = Get-SocialCachedExtras $Ws }
        $prof = $null
        try { $prof = Read-SocialProfile $Ws } catch { }
        $is = Test-SocialIsAdmin $prof $Extras
        if ($is -and $null -eq $script:adminTab) {
            $ti = New-Object System.Windows.Controls.TabItem
            $hdr = New-Object System.Windows.Controls.StackPanel; $hdr.Orientation = 'Horizontal'
            $g = New-Glyph 'EA18' 14; $g.Margin = '2,0,7,0'
            [void]$hdr.Children.Add($g)
            $ht = New-Object System.Windows.Controls.TextBlock; $ht.Text = 'Admin'; $ht.VerticalAlignment = 'Center'; $ht.Margin = '0,0,4,0'
            [void]$hdr.Children.Add($ht)
            $ti.Header = $hdr
            $dp = New-Object System.Windows.Controls.DockPanel; $dp.Margin = '10'
            $sv = New-Object System.Windows.Controls.ScrollViewer; $sv.VerticalScrollBarVisibility = 'Auto'
            $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '6,0,14,10'
            $sv.Content = $sp; [void]$dp.Children.Add($sv)
            $ti.Content = $dp
            $script:adminPanel = $sp
            [void]$script:tabs.Items.Add($ti)
            $script:adminTab = $ti
            if (@($script:TabOrder) -notcontains 'admin') { $script:TabOrder += 'admin' }
            Log 'admin: tab shown'
            Render-Admin
        }
        elseif (-not $is -and $null -ne $script:adminTab) {
            if ($script:tabs.SelectedItem -eq $script:adminTab) { $script:tabs.SelectedIndex = 0 }
            $script:tabs.Items.Remove($script:adminTab)
            $script:adminTab = $null; $script:adminReports = $null; $script:adminTopic = $null
            Log 'admin: tab removed'
        }
    } catch { Log "admin: tab - $_" }
}

function Invoke-AdminRefresh {
    $script:adminNote = 'Checking...'; Render-Admin
    try { $script:win.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) } catch { }
    $r = Get-AdminReports $Ws
    $script:adminReports = $r
    $script:adminTopic = Get-SocialNotifyTopic $Ws
    $script:adminNote = $(if ($r.Ok) { 'Updated ' + (Get-Date -Format 'h:mm tt') + '.' } else { $r.Message })
    Start-SocialFetch
    Render-Admin
}

function Render-Admin {
    $panel = $script:adminPanel
    if ($null -eq $panel) { return }
    $panel.Children.Clear()
    $top = New-Object System.Windows.Controls.StackPanel; $top.Orientation = 'Horizontal'; $top.Margin = '0,4,0,0'
    $rb = New-SocialButton 'Refresh' { Invoke-AdminRefresh }; $rb.Margin = '0'; $rb.FontWeight = 'Bold'
    [void]$top.Children.Add($rb)
    $nt = New-Text ('   ' + $script:adminNote) $ColDim 12; $nt.VerticalAlignment = 'Center'
    [void]$top.Children.Add($nt)
    [void]$panel.Children.Add($top)
    $players = @(Get-SocialPlayersNow)
    $ex = Get-SocialCachedExtras $Ws

    # --- reports ----------------------------------------------------------------
    [void]$panel.Children.Add((New-SectionHeader 'Reports and suggestions'))
    $rep = $script:adminReports
    if ($null -eq $rep) { [void]$panel.Children.Add((New-Text 'Press Refresh to load them.' $ColDim 13)) }
    elseif (-not $rep.Ok) { [void]$panel.Children.Add((New-Text $rep.Message $ColAway 13)) }
    elseif (@($rep.Items).Count -eq 0) { [void]$panel.Children.Add((New-Text 'Nothing open. Nice.' $ColDim 13)) }
    else {
        foreach ($i in @($rep.Items)) {
            $row = New-Object System.Windows.Controls.DockPanel; $row.Margin = '0,6,0,0'
            $btns = New-Object System.Windows.Controls.StackPanel; $btns.Orientation = 'Horizontal'; $btns.VerticalAlignment = 'Top'
            [System.Windows.Controls.DockPanel]::SetDock($btns, 'Right')
            [void]$btns.Children.Add((New-SocialButton 'Read' { param($s2, $e2) $it = $s2.Tag; [void](Show-ChoiceScroll $it.Title ($it.Title + "`n" + $it.When + "`n`n" + $it.Body)) } $i))
            [void]$btns.Children.Add((New-SocialButton 'Done' { param($s2, $e2) Invoke-AdminCloseReport $s2.Tag } $i))
            [void]$row.Children.Add($btns)
            $info = New-Object System.Windows.Controls.StackPanel
            [void]$info.Children.Add((New-Text $i.Title $ColText 14 $true))
            [void]$info.Children.Add((New-Text $i.When $ColDim 12))
            [void]$row.Children.Add($info)
            [void]$panel.Children.Add($row)
        }
    }

    # --- name requests ---------------------------------------------------------
    [void]$panel.Children.Add((New-SectionHeader 'Name requests'))
    $reqs = @(Get-AdminNameRequests $players $ex)
    if ($reqs.Count -eq 0) { [void]$panel.Children.Add((New-Text 'None waiting.' $ColDim 13)) }
    foreach ($p in $reqs) {
        $row = New-Object System.Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,6,0,0'
        $t = New-Text ("{0}  wants to be  {1}" -f $p.Username, $p.NameReq) $ColText 14; $t.Width = 360; $t.VerticalAlignment = 'Center'
        [void]$row.Children.Add($t)
        [void]$row.Children.Add((New-SocialButton 'Approve' { param($s2, $e2) Invoke-AdminName $s2.Tag $true } $p))
        [void]$row.Children.Add((New-SocialButton 'Decline' { param($s2, $e2) Invoke-AdminName $s2.Tag $false } $p))
        [void]$panel.Children.Add($row)
    }

    # --- the online library ------------------------------------------------------
    [void]$panel.Children.Add((New-IconHeader 'E898' 'Online library'))
    if ((Get-AdminLibKey $Ws) -eq '') {
        $t = New-Text 'Publishing needs a library key: a second GitHub key that can add files to the public repo. It stays on this drive only. One-time setup, about 3 minutes.' $ColDim 13
        [void]$panel.Children.Add($t)
        $kb = New-SocialButton 'Set up the library key...' { Invoke-AdminLibKey }; $kb.Margin = '0,8,0,0'; $kb.HorizontalAlignment = 'Left'
        [void]$panel.Children.Add($kb)
    }
    else {
        $t = New-Text 'Pick a game file, answer a few questions, and it goes online by itself: the file is uploaded and the library list updated. Only games that may be shared: homebrew, freeware, fan-made, your own. Up to 2 GB each.' $ColDim 13
        [void]$panel.Children.Add($t)
        $row = New-Object System.Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,8,0,0'
        $pb = New-SocialButton 'Publish a game...' { Invoke-AdminPublish }; $pb.Margin = '0'; $pb.FontWeight = 'Bold'
        $pb.IsEnabled = ($null -eq $script:adminLibJob)
        [void]$row.Children.Add($pb)
        $kb = New-SocialButton 'New key...' { Invoke-AdminLibKey }; $kb.FontSize = 11; $kb.Padding = '6,1'
        [void]$row.Children.Add($kb)
        [void]$panel.Children.Add($row)
        $script:adminLibText = New-Text $(if ($null -ne $script:adminLibJob) { 'Working...' } else { '' }) $ColAway 13
        $script:adminLibText.Margin = '0,6,0,0'
        [void]$panel.Children.Add($script:adminLibText)
    }

    # --- phone alerts ----------------------------------------------------------
    [void]$panel.Children.Add((New-SectionHeader 'Phone alerts'))
    if ($null -eq $script:adminTopic) { [void]$panel.Children.Add((New-Text 'Press Refresh to see the alert channel.' $ColDim 13)) }
    elseif ($script:adminTopic -eq '') {
        [void]$panel.Children.Add((New-Text 'Off. Turn it on and your phone buzzes for every new report and name request (free ntfy app).' $ColDim 13))
        $ab = New-SocialButton 'Turn on phone alerts' { Invoke-AdminTopic }; $ab.Margin = '0,8,0,0'; $ab.HorizontalAlignment = 'Left'
        [void]$panel.Children.Add($ab)
    }
    else {
        $t = New-Text ("In the ntfy app, subscribe to:   {0}" -f $script:adminTopic) $ColText 14
        [void]$panel.Children.Add($t)
        $row = New-Object System.Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,8,0,0'
        $cb = New-SocialButton 'Copy' { try { [System.Windows.Clipboard]::SetText([string]$script:adminTopic); $script:adminNote = 'Copied.'; Render-Admin } catch { } }; $cb.Margin = '0'
        [void]$row.Children.Add($cb)
        [void]$row.Children.Add((New-SocialButton 'Send a test' { $ok = Send-SocialNotify $Ws 'Test' 'Phone alerts work.'; $script:adminNote = $(if ($ok) { 'Test sent.' } else { 'Could not send.' }); Render-Admin }))
        [void]$row.Children.Add((New-SocialButton 'New channel' { Invoke-AdminTopic }))
        [void]$panel.Children.Add($row)
    }

    # --- admins -------------------------------------------------------------------
    [void]$panel.Children.Add((New-SectionHeader 'Admins'))
    $me = $null; try { $me = Read-SocialProfile $Ws } catch { }
    foreach ($id in @($ex.Admins)) {
        $who = @($players | Where-Object { $null -ne $_ -and $_.Id -eq $id }) | Select-Object -First 1
        $row = New-Object System.Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,4,0,0'
        $t = New-Text $(if ($null -ne $who) { $who.Username } else { "($id)" }) $ColText 14; $t.Width = 220; $t.VerticalAlignment = 'Center'
        [void]$row.Children.Add($t)
        if ($null -ne $me -and $id -ne $me.Id) { [void]$row.Children.Add((New-SocialButton 'Remove' { param($s2, $e2) Invoke-AdminSetAdmin ([string]$s2.Tag) $false } $id)) }
        [void]$panel.Children.Add($row)
    }
    $ad = New-SocialButton 'Make someone an admin...' { Invoke-AdminAdd }; $ad.Margin = '0,8,0,0'; $ad.HorizontalAlignment = 'Left'
    [void]$panel.Children.Add($ad)
    $d = New-Text 'A light lock like the rest of the friends system: the shared key could change these lists, so keep admins to people you trust.' '#FF777780' 11
    $d.Margin = '0,14,0,0'
    [void]$panel.Children.Add($d)
}

function Invoke-AdminCloseReport($Item) {
    if (Close-AdminReport $Ws $Item.Number) {
        $script:adminReports.Items = @(@($script:adminReports.Items) | Where-Object { $_.Number -ne $Item.Number })
        $script:adminNote = 'Marked done.'
    } else { $script:adminNote = 'GitHub would not close it. Try Refresh.' }
    Render-Admin
}

function Invoke-AdminName($Player, [bool]$Approve) {
    if ($Approve -and (Test-SocialNameTaken @(Get-SocialPlayersNow) $Player.NameReq $Player.Id)) {
        [void](Show-Choice $WizardName "Somebody else already has the name $($Player.NameReq). Decline this one." @('OK')); return
    }
    if (Set-AdminNameAnswer $Ws $Player.Id $Player.NameReq $Approve) {
        $script:adminNote = $(if ($Approve) { "Approved. $($Player.Username) becomes $($Player.NameReq) the next time their wizard checks in." } else { 'Declined.' })
        Log ("admin: name {0} -> {1} {2}" -f $Player.Username, $Player.NameReq, $(if ($Approve) { 'approved' } else { 'declined' }))
        # Taken in at once here, so the request leaves this list straight away.
        $script:socialFetched = $null
        Start-SocialFetch
    } else { $script:adminNote = 'GitHub would not take it. Try again.' }
    Render-Admin
}

function Invoke-AdminSetAdmin([string]$Id, [bool]$Add) {
    $ex = Get-SocialCachedExtras $Ws
    $ids = @($ex.Admins)
    if ($Add) { $ids = @($ids + $Id) } else {
        if ((Show-Choice $WizardName 'Take away their Admin tab?' @('Remove', 'Cancel')) -ne 'Remove') { return }
        $ids = @($ids | Where-Object { $_ -ne $Id })
    }
    if (Set-AdminList $Ws $ids) { $script:adminNote = 'Saved. It shows up for them within a couple of minutes.'; Log ("admin: admins now {0}" -f ($ids -join ',')); Start-SocialFetch }
    else { $script:adminNote = 'GitHub would not take it.' }
    Render-Admin
}

function Invoke-AdminAdd {
    $name = (Show-TextInput $WizardName 'Their username, exactly as it shows on the Profile tab:' '').Trim()
    if ($name -eq '') { return }
    $who = @(Get-SocialPlayersNow | Where-Object { $null -ne $_ -and $_.Username -eq $name }) | Select-Object -First 1
    if ($null -eq $who) { [void](Show-Choice $WizardName "Nobody called '$name'. Press Refresh first if they are new." @('OK')); return }
    if ((Show-Choice $WizardName "Make $($who.Username) an admin?`n`nThey get the Admin tab: reports, name requests, publishing to the library (with their own library key), and the admins list." @('Make admin', 'Cancel')) -ne 'Make admin') { return }
    Invoke-AdminSetAdmin $who.Id $true
}

function Invoke-AdminTopic {
    $t = New-AdminNotifyTopic
    if (Set-AdminNotifyTopic $Ws $t) { $script:adminTopic = $t; $script:adminNote = 'Phone alerts are on. Subscribe to the channel in the ntfy app.' }
    else { $script:adminNote = 'GitHub would not take it.' }
    Render-Admin
}

function Invoke-AdminLibKey {
    $steps = "One-time setup, on github.com (signed in as you):`n`n" +
             "1. Click your picture (top right) > Settings.`n" +
             "2. At the bottom left: Developer settings > Personal access tokens > Fine-grained tokens > Generate new token.`n" +
             "3. Name: wizard library. Expiration: the longest it offers.`n" +
             "4. Repository access: Only select repositories > retrobat-wizard.`n" +
             "5. Permissions > Repository permissions > Contents: Read and write.`n" +
             "6. Generate token, copy it, and paste it here:"
    $k = (Show-TextInput $WizardName $steps '').Trim()
    if ($k -eq '') { return }
    if (-not (Set-AdminLibKey $Ws $k)) { [void](Show-Choice $WizardName 'That does not look like a GitHub key (they start with github_pat_).' @('OK')); return }
    $r = Invoke-AdminLibApi $k 'GET' "https://api.github.com/repos/$script:AdminLibRepo"
    $script:adminNote = $(if ($r.Status -eq 200) { 'Library key saved and working.' } else { "Saved, but GitHub answered $($r.Status). Check the key's settings." })
    Log ("admin: library key saved, test {0}" -f $r.Status)
    Render-Admin
}

function Invoke-AdminPublish {
    if ($null -ne $script:adminLibJob -or -not $script:gamesOk) { return }
    try {
        Add-Type -AssemblyName PresentationFramework
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Title = 'Choose a game to put in the online library'
        $dlg.InitialDirectory = (Join-Path $Root 'roms')
        if (-not $dlg.ShowDialog()) { return }
    } catch { return }
    $f = $dlg.FileName
    $sys = Resolve-GameConsole $f
    if ($null -eq $sys) { return }
    $info = Get-LibGamelistInfo $sys $f
    $title = (Show-TextInput $WizardName 'The name people see in the library:' $info.Title).Trim()
    if ($title -eq '') { return }
    $players = Show-TextInput $WizardName 'How many players? (like 1, 1-2, 1-4)' $info.Players
    $desc = Show-TextInput $WizardName 'One or two lines about it:' $info.Description
    $mb = [math]::Round((Get-Item -LiteralPath $f).Length / 1MB, 1)
    $ok = Show-Choice $WizardName ("Publish '{0}' ({1}, {2} MB) to the online library?`n`nEveryone with the wizard can download it. Only games that may be shared: homebrew, freeware, fan-made, your own." -f $title, $sys.FullName, $mb) @('Publish', 'Cancel')
    if ($ok -ne 'Publish') { return }
    try {
        $sync = [hashtable]::Synchronized(@{ Stage = 'Starting...'; Percent = 0 })
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        try { $iss.ExecutionPolicy = 'Bypass' } catch { }
        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss); $rs.Open()
        $ps = [System.Management.Automation.PowerShell]::Create(); $ps.Runspace = $rs
        [void]$ps.AddScript('param($s, $a, $ws, $f, $sys, $t, $pl, $d, $sync) . $s; . $a; Publish-AdminLibraryGame $ws $f $sys $t $pl $d $sync')
        foreach ($arg in @($script:socialLib, (Join-Path $ScriptsDir 'AdminEngine.ps1'), $Ws, $f, $sys.Name, $title, [string]$players, [string]$desc, $sync)) { [void]$ps.AddArgument($arg) }
        $script:adminLibJob = [pscustomobject]@{ Ps = $ps; Handle = $ps.BeginInvoke(); Sync = $sync; Title = $title }
        Log ("admin: publishing {0} ({1})" -f $title, $sys.Name)
        $script:adminLibTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:adminLibTimer.Interval = [TimeSpan]::FromMilliseconds(800)
        $script:adminLibTimer.Add_Tick({ Invoke-AdminPublishTick })
        $script:adminLibTimer.Start()
    } catch { Log "admin: publish could not start - $_"; $script:adminLibJob = $null }
    Render-Admin
}

function Invoke-AdminPublishTick {
    try {
        $j = $script:adminLibJob
        if ($null -eq $j) { $script:adminLibTimer.Stop(); return }
        if (-not $j.Handle.IsCompleted) {
            if ($null -ne $script:adminLibText) {
                $txt = [string]$j.Sync.Stage
                if ($txt -eq 'Uploading...') { $txt = 'Uploading... {0}%' -f $j.Sync.Percent }
                $script:adminLibText.Text = $txt
            }
            return
        }
        $script:adminLibTimer.Stop()
        $out = $null
        try { $out = @($j.Ps.EndInvoke($j.Handle)) } catch { $out = @(@{ Ok = $false; Message = $_.Exception.Message }) }
        try { $j.Ps.Runspace.Dispose(); $j.Ps.Dispose() } catch { }
        $script:adminLibJob = $null
        $r = $(if ($out.Count -gt 0) { $out[-1] } else { @{ Ok = $false; Message = 'No answer.' } })
        Log ("admin: publish {0} - {1}" -f $j.Title, $r.Message)
        $script:adminNote = $r.Message
        $script:libCatalog = $null
        Render-Admin
        [void](Show-Choice $WizardName $r.Message @('OK'))
    } catch { Log "admin: publish tick - $_" }
}

# Checks the name with GitHub (one request). Offline, it is allowed with a
# warning: a clash only means two people share a name in a search.
function Test-SocialNameFree([string]$Name, [string]$MyId) {
    $why = Test-SocialUsername $Name
    if ($why -ne '') { [void](Show-Choice $WizardName ("That name will not work.`n`n" + $why) @('OK')); return $false }
    $all = Get-SocialPlayers $Ws
    if ($all.Ok) { $list = @($all.Players) } else { $list = @(Get-SocialCachedPlayers $Ws) }
    if (Test-SocialNameTaken $list $Name $MyId) {
        [void](Show-Choice $WizardName "Somebody already has that name. Pick another one." @('OK'))
        return $false
    }
    if (-not $all.Ok) { Log "profile: name checked against the cache only - $($all.Message)" }
    return $true
}

# A custom picture: square it, shrink it to 64 x 64, save it in profile\ and
# send it. Pixel art that is already small is scaled with hard edges, a photo
# smoothly.
function Complete-SocialPicture($Prof, $Ed) {
    if ($Ed.Avatar -ne 'custom:new') { return }
    $P = Get-SocialPaths $Ws
    New-SocialDir $P.ProfileDir
    $ok = $false
    try {
        Add-Type -AssemblyName System.Drawing
        $src = [System.Drawing.Image]::FromFile($Ed.File)
        try {
            $side = [math]::Min($src.Width, $src.Height)
            $sx = [int](($src.Width - $side) / 2); $sy = [int](($src.Height - $side) / 2)
            $bmp = New-Object System.Drawing.Bitmap 64, 64
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            # Pixel art (anything up to 256 across) keeps hard edges; a photo
            # is smoothed. Steven's own pixel mage was 138 x 150.
            if ($side -le 256) { $g.InterpolationMode = 'NearestNeighbor'; $g.PixelOffsetMode = 'Half' }
            else { $g.InterpolationMode = 'HighQualityBicubic' }
            $g.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, 64, 64), (New-Object System.Drawing.Rectangle $sx, $sy, $side, $side), [System.Drawing.GraphicsUnit]::Pixel)
            $g.Dispose()
            $tmp = $P.Avatar + '.new'
            $bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
        }
        finally { $src.Dispose() }
        Copy-Item -LiteralPath $tmp -Destination $P.Avatar -Force
        Remove-Item -LiteralPath $tmp -Force
        $ok = $true
    }
    catch { Log ("profile: picture could not be read - {0}" -f $_.Exception.Message) }
    if (-not $ok) {
        [void](Show-Choice $WizardName "That picture could not be opened, so your pixel icon stays.`n`nPNG, JPG, GIF and BMP all work." @('OK'))
        $Prof.Avatar = 'icon:gameboy'
        return
    }
    $tag = Publish-SocialAvatar $Ws $Prof
    if ($tag -eq '') {
        $Prof.Avatar = 'icon:gameboy'
        [void](Show-Choice $WizardName "Your picture could not be sent to GitHub (no internet?). A pixel icon is used for now; try again from Change name or picture." @('OK'))
    }
    else { $Prof.Avatar = $tag }
}

# The name and picture window. Returns @{ Ok; Name; Avatar; File } where Avatar
# is 'icon:<name>', the existing 'custom:...', or 'custom:new' with File set.
function Show-SocialEditor([string]$Title, [string]$Name, [string]$Avatar, [bool]$PictureOnly = $false) {
    Close-Splash
    $w = New-Object System.Windows.Window
    $w.Title = $Title; $w.Width = 560; $w.SizeToContent = 'Height'
    $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'NoResize'
    $w.Background = (New-Brush $ColBg); $w.Topmost = $true
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '22'
    $n1 = New-Text 'Your name' $ColText 15 $true
    $n2 = New-Text 'What friends search for. 3 to 20 letters, numbers, spaces, dots and dashes.' $ColDim 12
    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Text = $Name; $tb.FontSize = 15; $tb.Margin = '0,6,0,0'; $tb.Padding = '4,3'; $tb.MaxLength = 20
    foreach ($el in @($n1, $n2, $tb)) { if ($PictureOnly) { $el.Visibility = 'Collapsed' }; [void]$sp.Children.Add($el) }
    $h = New-Text 'Picture' $ColText 15 $true; $h.Margin = $(if ($PictureOnly) { '0' } else { '0,18,0,0' })
    [void]$sp.Children.Add($h)
    $wrap = New-Object System.Windows.Controls.WrapPanel; $wrap.Margin = '0,10,0,0'
    $script:iconButtons = @()
    foreach ($n in $script:AvatarIcons) {
        $bmp = Get-PixelBitmap (Join-Path $WizardDir ('profile-' + $n + '.png'))
        if ($null -eq $bmp) { continue }
        $b = New-Object System.Windows.Controls.Button
        $b.Tag = 'icon:' + $n; $b.Margin = '0,0,8,8'; $b.Cursor = 'Hand'; $b.Width = 68; $b.Height = 60; $b.ToolTip = $n
        $img = New-Object System.Windows.Controls.Image
        $img.Source = $bmp; $img.Stretch = 'None'
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, [System.Windows.Media.BitmapScalingMode]::NearestNeighbor)
        $b.Content = $img
        $b.Add_Click({ param($s2, $e2) Select-ProfileIconButton ([string]$s2.Tag) })
        $script:iconButtons += $b
        [void]$wrap.Children.Add($b)
    }
    $own = New-Object System.Windows.Controls.Button
    $own.Tag = 'custom:new'; $own.Margin = '0,0,8,8'; $own.Padding = '10,6'; $own.FontSize = 12; $own.Height = 60
    $own.Content = 'My own picture...'
    if ($Avatar -like 'custom:*' -and $Avatar -ne 'custom:new') { $own.Tag = $Avatar; $own.Content = 'My own picture' }
    $script:socialOwnBtn = $own
    $own.Add_Click({
        param($s2, $e2)
        try {
            Add-Type -AssemblyName PresentationFramework
            $dlg = New-Object Microsoft.Win32.OpenFileDialog
            $dlg.Filter = 'Pictures|*.png;*.jpg;*.jpeg;*.gif;*.bmp'
            $dlg.Title = 'Choose a picture'
            if ($dlg.ShowDialog()) {
                $script:socialPicFile = $dlg.FileName
                $s2.Tag = 'custom:new'
                $s2.Content = 'My own: ' + (Split-Path -Leaf $dlg.FileName)
                Select-ProfileIconButton 'custom:new'
            }
        } catch { Log "profile: picture dialog - $_" }
    })
    $script:iconButtons += $own
    [void]$wrap.Children.Add($own)
    [void]$sp.Children.Add($wrap)
    [void]$sp.Children.Add((New-Text 'Your own picture is cut to a square and shrunk to 64 x 64 before it is sent.' $ColDim 12))

    $script:socialPicFile = ''
    $script:profEditIcon = $Avatar
    $script:profEditOk = $false
    $script:profEditWin = $w
    $script:profEditName = $tb
    Select-ProfileIconButton $Avatar

    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.HorizontalAlignment = 'Right'; $row.Margin = '0,14,0,0'
    $cancel = New-Object System.Windows.Controls.Button
    $cancel.Content = 'Cancel'; $cancel.Padding = '16,7'; $cancel.FontSize = 14
    $cancel.Add_Click({ $script:profEditOk = $false; $script:profEditWin.Close() })
    $save = New-Object System.Windows.Controls.Button
    $save.Content = 'Save'; $save.Padding = '16,7'; $save.FontSize = 14; $save.Margin = '8,0,0,0'
    $save.Add_Click({ $script:profEditOk = $true; $script:profEditWin.Close() })
    [void]$row.Children.Add($cancel); [void]$row.Children.Add($save)
    [void]$sp.Children.Add($row)
    $w.Content = $sp
    [void]$w.ShowDialog()

    $out = @{ Ok = $script:profEditOk; Name = ([string]$script:profEditName.Text).Trim(); Avatar = [string]$script:profEditIcon; File = $script:socialPicFile }
    if ($out.Avatar -eq '') { $out.Avatar = 'icon:gameboy' }
    if ($out.Avatar -eq 'custom:new' -and $out.File -eq '') { $out.Avatar = 'icon:gameboy' }
    if ($out.Name -eq '') { $out.Ok = $false }
    return $out
}

# ===========================================================================
#  UPDATES                                                       (2026-10-10)
# ===========================================================================
#  The wizard only ever LOOKS. When the window opens it reads one tiny file on
#  GitHub (latest.ini) in the background and, if there is a newer version,
#  shows the bar at the top. Nothing downloads and nothing installs until
#  somebody presses Update now (Steven's call, 2026-10-10: no surprise waits
#  when the wizard is reopened). The button then closes the wizard and hands
#  over to scripts\Updater.ps1 in its own process, which downloads, checks,
#  installs and opens the wizard again.
#
#  THE LOOK RUNS IN A SECOND RUNSPACE so the window never waits on the
#  network. It only writes update\status.ini; this side reads that file on a
#  timer. The runspace never touches the window, which WPF would refuse.
#
#  IT CAN NEVER BE THE PROBLEM. Every part is wrapped. No UpdateEngine.ps1,
#  no internet, GitHub down: no bar, a line in the log, and everything else
#  works exactly as before.
# ---------------------------------------------------------------------------
$script:updPs     = $null
$script:updHandle = $null
$script:updTimer  = $null
$script:updateNote = $null

function Start-UpdatePeek {
    if (-not $script:updateOk) { return }
    if ($null -ne $script:updHandle) { return }   # one at a time
    try {
        Set-UpdateNote 'Checking GitHub...'
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        try { $iss.ExecutionPolicy = 'Bypass' } catch { }
        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
        $rs.Open()
        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $rs
        # Bug reports saved while there was no internet go out on the same
        # trip. Guarded on its own: a problem there never touches the check.
        [void]$ps.AddScript('param($lib, $ws, $soc, $bug) . $lib; [void](Invoke-UpdateCheck -Ws $ws -NoDownload); if ($bug -ne '''') { try { . $soc; . $bug; [void](Send-BugOutbox $ws) } catch { } }')
        [void]$ps.AddArgument($script:updLib)
        [void]$ps.AddArgument($Ws)
        [void]$ps.AddArgument($script:socialLib)
        [void]$ps.AddArgument($(if ($script:bugOk) { $script:bugLib } else { '' }))
        $script:updPs = $ps
        $script:updHandle = $ps.BeginInvoke()
        $script:updTicks = 0
        $script:updTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:updTimer.Interval = [TimeSpan]::FromMilliseconds(700)
        $script:updTimer.Add_Tick({ Invoke-UpdatePeekTick })
        $script:updTimer.Start()
    }
    catch {
        Log ("update check: could not start - {0}" -f $_.Exception.Message)
        $script:updHandle = $null
        Set-UpdateNote 'The update check could not start. Details in wizard.log.'
    }
}

function Invoke-UpdatePeekTick {
    try {
        $script:updTicks++
        if ($null -eq $script:updHandle) { $script:updTimer.Stop(); return }
        if (-not $script:updHandle.IsCompleted) {
            # About ninety seconds. The fetch itself gives up after sixty.
            if ($script:updTicks -gt 130) {
                $script:updTimer.Stop()
                Log 'update check: no answer, gave up waiting'
                Set-UpdateNote 'No answer from GitHub. Try again later.'
            }
            return
        }
        $script:updTimer.Stop()
        try { [void]$script:updPs.EndInvoke($script:updHandle) }
        catch { Log ("update check: {0}" -f $_.Exception.Message) }
        try { $script:updPs.Runspace.Dispose(); $script:updPs.Dispose() } catch { }
        $script:updPs = $null
        $script:updHandle = $null
        Show-UpdateState
    }
    catch { Log ("update check tick: {0}" -f $_.Exception.Message) }
}

# Reads update\status.ini and puts it on screen: the bar for a new version,
# one line on the Help tab for everything else.
function Show-UpdateState {
    $st = @{}
    try { $st = Read-UpdStatus $Ws } catch { }
    $state = [string]$st['state']
    $ver   = [string]$st['version']
    $msg   = [string]$st['message']
    Log ("update check: {0} (GitHub {1}, here {2})" -f $state, $ver, $WizardVersion)
    switch ($state) {
        { $_ -eq 'available' -or $_ -eq 'ready' } {
            if ($null -ne $script:updateBar) {
                $script:updateBarText.Text = ("Version {0} is out. This drive has {1}." -f $ver, $WizardVersion)
                $script:updateBar.Visibility = 'Visible'
            }
            Set-UpdateNote ("Version {0} is out. Press Update now at the top." -f $ver)
        }
        'uptodate' {
            $line = "Up to date: version $WizardVersion."
            if ($msg -ne '') { $line += ' ' + $msg }
            Set-UpdateNote $line
        }
        'busy'    { Set-UpdateNote 'Already checking.' }
        default {
            if ($msg -ne '') { Set-UpdateNote $msg } else { Set-UpdateNote 'Could not check for updates.' }
        }
    }
}

function Set-UpdateNote([string]$Text) {
    if ($null -ne $script:updateNote) { try { $script:updateNote.Text = $Text } catch { } }
}

function Show-UpdateNotes {
    $st = @{}
    try { $st = Read-UpdStatus $Ws } catch { }
    $notes = [string]$st['notes']
    if ($notes -eq '') { $notes = 'No notes came with this version.' }
    else { $notes = '- ' + ($notes -replace ' \| ', "`n- ") }
    [void](Show-Choice $WizardName ("What's new in version {0}:`n`n{1}" -f [string]$st['version'], $notes) @('OK'))
}

# The two buttons that change files: Update now, and Go back one update. Both
# hand over to scripts\Updater.ps1 in its own process and close the wizard,
# because nothing should be replaced while this window holds it open.
function Invoke-WizardUpdate([string]$Mode) {
    if (Test-RetroBatRunning) {
        [void](Show-Choice $WizardName 'RetroBat is open. Close it completely first, then try again.' @('OK'))
        return
    }
    $updater = Join-Path $ScriptsDir 'Updater.ps1'
    if (-not (Test-Path -LiteralPath $updater)) {
        [void](Show-Choice $WizardName 'scripts\Updater.ps1 is missing, so this cannot be done from here.' @('OK'))
        return
    }
    if ($Mode -eq 'GoBack') {
        $info = $null
        try { $info = Get-UpdGoBackInfo $Ws } catch { }
        if ($null -eq $info) { [void](Show-Choice $WizardName 'There is no update to go back from.' @('OK')); return }
        $pick = Show-Choice $WizardName ("Go back from version {0} to {1}?`n`nThe wizard closes, puts the old files back and opens again. That version will not be offered again, but a newer one will." -f $info.To, $info.From) @('Go back', 'Cancel')
        if ($pick -ne 'Go back') { return }
    }
    else {
        $st = @{}
        try { $st = Read-UpdStatus $Ws } catch { }
        $pick = Show-Choice $WizardName ("Update to version {0} now?`n`nThe wizard closes, downloads what changed, installs it and opens again. Usually under a minute. Saves, games and settings are not touched, and the Help tab can go back one update." -f [string]$st['version']) @('Update now', 'Not now')
        if ($pick -ne 'Update now') { return }
    }
    try {
        $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $argLine = '-NoProfile -ExecutionPolicy Bypass -Command "& ''{0}'' -Mode {1} -WaitPid {2} -Relaunch"' -f ($updater -replace "'", "''"), $Mode, $PID
        Start-Process -FilePath $ps -ArgumentList $argLine -WindowStyle Hidden
        Log ("update: handed over to Updater.ps1, mode {0}" -f $Mode)
        $script:win.Close()
    }
    catch {
        Log ("update: could not start Updater.ps1 - {0}" -f $_.Exception.Message)
        [void](Show-Choice $WizardName "The updater could not be started.`n`nDetails are in wizard.log." @('OK'))
    }
}

# A problem inside the open window. Never closes it unless asked to.
$script:softCrashBusy = $false
function Invoke-SoftCrash($Ex) {
    if ($script:softCrashBusy) { return }
    $script:softCrashBusy = $true
    try {
        $inner = $Ex
        while ($null -ne $inner.InnerException) { $inner = $inner.InnerException }
        $msg = [string]$inner.Message
        $stack = ''
        try { if ($inner.ErrorRecord) { $stack = [string]$inner.ErrorRecord.ScriptStackTrace + "`n" + [string]$inner.ErrorRecord.InvocationInfo.PositionMessage } } catch { }
        Log ("CAUGHT (window kept open): {0}" -f $msg)
        if ($stack) { Log $stack }
        $buttons = @('Keep going', 'Close the wizard')
        if ($script:bugOk) { $buttons = @('Send a report', 'Keep going', 'Close the wizard') }
        $pick = Show-Choice $WizardName ("Something went wrong:`n`n$msg`n`nThe wizard is still open. Sending a report helps get it fixed (it holds the error and the recent logs, with your Windows name taken out).") $buttons
        if ($pick -eq 'Send a report') {
            $body = New-BugReport $Ws 'Something went wrong in the wizard (sent from the error message).' $true ($msg + "`n" + $stack)
            $r = Send-BugReport $Ws (Get-BugTitle '' $msg) $body
            Log ("crash report: {0}" -f $r.Message)
            $pick = Show-Choice $WizardName ($r.Message) @('Keep going', 'Close the wizard')
        }
        if ($pick -eq 'Close the wizard') { try { $script:win.Close() } catch { } }
    }
    finally { $script:softCrashBusy = $false }
}

# ===========================================================================
#  REPORT A BUG                                                  (2026-10-10)
# ===========================================================================
#  The engine is scripts\BugReport.ps1. Sent to the private social repo as a
#  GitHub Issue; the person sees exactly what goes before it goes.
function Add-BugAction {
    if ($null -eq $script:helpPanel -or -not $script:bugOk) { return }
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.Margin = '0,16,0,0'
    $b = New-Object System.Windows.Controls.Button
    $b.Content = 'Report a bug'; $b.Padding = '10,3'; $b.FontSize = 13; $b.VerticalAlignment = 'Top'
    $b.Add_Click({ Show-BugDialog 'bug' })
    [void]$row.Children.Add($b)
    $b2 = New-Object System.Windows.Controls.Button
    $b2.Content = 'Suggest something'; $b2.Padding = '10,3'; $b2.FontSize = 13; $b2.VerticalAlignment = 'Top'; $b2.Margin = '8,0,0,0'
    $b2.Add_Click({ Show-BugDialog 'idea' })
    [void]$row.Children.Add($b2)
    $t = New-Text 'Something broken? A feature or a game you would like? Say it here and it goes straight to whoever keeps this wizard.' $ColDim 13
    $t.Margin = '12,7,0,0'; $t.MaxWidth = 470; $t.TextWrapping = 'Wrap'
    [void]$row.Children.Add($t)
    [void]$script:helpPanel.Children.Add($row)
}

$script:BugKinds = @(
    @{ Key = 'bug';  Label = 'Bug - something is broken';     Head = 'What happened?';   Hint = 'What you were doing, and what went wrong. One line is fine.' },
    @{ Key = 'idea'; Label = 'Feature or idea';               Head = 'Your idea';        Hint = 'What would make the wizard or the drive better?' },
    @{ Key = 'game'; Label = 'Game request';                  Head = 'Which game?';      Hint = 'The game and its console. A reason helps, like "great 4-player party game".' }
)

function Update-BugKind {
    $k = $script:BugKinds[[math]::Max(0, $script:bugKindBox.SelectedIndex)]
    $script:bugHead.Text = $k.Head
    $script:bugHint.Text = $k.Hint
    # Logs are for bugs. A suggestion does not need them, so they start off.
    $script:bugLogs.IsChecked = ($k.Key -eq 'bug')
}

function Show-BugDialog([string]$Kind = 'bug') {
    Close-Splash
    $w = New-Object System.Windows.Window
    $w.Title = 'Report a bug or suggest something'; $w.Width = 560; $w.SizeToContent = 'Height'
    $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'NoResize'
    $w.Background = (New-Brush $ColBg); $w.Topmost = $true
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '22'
    $kb = New-Object System.Windows.Controls.ComboBox
    $kb.FontSize = 13; $kb.Width = 260; $kb.HorizontalAlignment = 'Left'; $kb.Margin = '0,0,0,14'
    foreach ($k in $script:BugKinds) { [void]$kb.Items.Add($k.Label) }
    $script:bugKindBox = $kb
    [void]$sp.Children.Add($kb)
    $hd = New-Text '' $ColText 15 $true; $script:bugHead = $hd
    [void]$sp.Children.Add($hd)
    $hn = New-Text '' $ColDim 12; $script:bugHint = $hn
    [void]$sp.Children.Add($hn)
    $tb = New-Object System.Windows.Controls.TextBox
    $tb.AcceptsReturn = $true; $tb.TextWrapping = 'Wrap'; $tb.Height = 110; $tb.FontSize = 14
    $tb.Margin = '0,8,0,0'; $tb.Padding = '4,3'; $tb.VerticalScrollBarVisibility = 'Auto'
    [void]$sp.Children.Add($tb)
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Content = 'Include the recent logs (they help a lot)'; $cb.IsChecked = $true
    $cb.Foreground = (New-Brush $ColText); $cb.FontSize = 13; $cb.Margin = '0,10,0,0'
    [void]$sp.Children.Add($cb)
    $n = New-Text 'Your Windows name and computer name are taken out of the logs first. Sent even in guest mode, only because you press Send.' $ColDim 12
    $n.TextWrapping = 'Wrap'; $n.Margin = '0,6,0,0'
    [void]$sp.Children.Add($n)
    $script:bugText = $tb; $script:bugLogs = $cb; $script:bugWin = $w; $script:bugChoice = ''
    $start = 0
    for ($i = 0; $i -lt $script:BugKinds.Count; $i++) { if ($script:BugKinds[$i].Key -eq $Kind) { $start = $i } }
    $kb.SelectedIndex = $start
    Update-BugKind
    $kb.Add_SelectionChanged({ Update-BugKind })
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.HorizontalAlignment = 'Right'; $row.Margin = '0,16,0,0'
    foreach ($label in @('See what is sent', 'Cancel', 'Send')) {
        $bb = New-Object System.Windows.Controls.Button
        $bb.Content = $label; $bb.Tag = $label; $bb.Padding = '14,6'; $bb.FontSize = 14; $bb.Margin = '8,0,0,0'
        $bb.Add_Click({
            param($s2, $e2)
            $script:bugChoice = [string]$s2.Tag
            if ($script:bugChoice -eq 'See what is sent') {
                $kk = $script:BugKinds[[math]::Max(0, $script:bugKindBox.SelectedIndex)].Key
                $body = New-BugReport $Ws ([string]$script:bugText.Text) ([bool]$script:bugLogs.IsChecked) '' $kk
                Show-BugPreview $body
                return
            }
            $script:bugWin.Close()
        })
        [void]$row.Children.Add($bb)
    }
    [void]$sp.Children.Add($row)
    $w.Content = $sp
    [void]$w.ShowDialog()
    if ($script:bugChoice -ne 'Send') { return }
    $what = [string]$script:bugText.Text
    $kk = $script:BugKinds[[math]::Max(0, $script:bugKindBox.SelectedIndex)].Key
    $body = New-BugReport $Ws $what ([bool]$script:bugLogs.IsChecked) '' $kk
    $r = Send-BugReport $Ws (Get-BugTitle $what '' $kk) $body
    Log ("bug report: {0}" -f $r.Message)
    [void](Show-Choice $WizardName $r.Message @('OK'))
}

function Show-BugPreview([string]$Body) {
    $w = New-Object System.Windows.Window
    $w.Title = 'Exactly what is sent'; $w.Width = 720; $w.Height = 520
    $w.WindowStartupLocation = 'CenterScreen'; $w.Background = (New-Brush $ColBg); $w.Topmost = $true
    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Text = $Body; $tb.IsReadOnly = $true; $tb.FontFamily = 'Consolas'; $tb.FontSize = 12
    $tb.VerticalScrollBarVisibility = 'Auto'; $tb.HorizontalScrollBarVisibility = 'Auto'; $tb.Margin = '10'
    $w.Content = $tb
    [void]$w.ShowDialog()
}

# The Updates row on the Help tab: one line of status, Check for updates, and
# Go back one update when there is an update to go back from.
function Add-UpdateActions {
    if ($null -eq $script:helpPanel -or -not $script:updateOk) { return }
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.Margin = '0,16,0,0'

    $b = New-Object System.Windows.Controls.Button
    $b.Content = 'Check for updates'
    $b.Padding = '10,3'; $b.FontSize = 13; $b.VerticalAlignment = 'Top'
    $b.Add_Click({ Start-UpdatePeek })
    [void]$row.Children.Add($b)

    $info = $null
    try { $info = Get-UpdGoBackInfo $Ws } catch { }
    if ($null -ne $info) {
        $b2 = New-Object System.Windows.Controls.Button
        $b2.Content = 'Go back one update'
        $b2.Padding = '10,3'; $b2.FontSize = 13; $b2.VerticalAlignment = 'Top'; $b2.Margin = '8,0,0,0'
        $b2.Add_Click({ Invoke-WizardUpdate 'GoBack' })
        [void]$row.Children.Add($b2)
    }

    $t = New-Text ("Version $WizardVersion.") $ColDim 13
    $t.Margin = '12,7,0,0'; $t.MaxWidth = 400; $t.TextWrapping = 'Wrap'
    $script:updateNote = $t
    [void]$row.Children.Add($t)
    [void]$script:helpPanel.Children.Add($row)
}


function Render-Help {
    if ($null -eq $script:helpPanel) { return }
    $script:helpPanel.Children.Clear()

    if (-not $script:helpOk) {
        [void]$script:helpPanel.Children.Add(
            (New-Text 'HelpText.ps1 is missing from the scripts folder.' $ColText 14 $true))
        [void]$script:helpPanel.Children.Add(
            (New-Text 'Everything is explained in _ClaudeWorkspace\docs\CUSTOMIZATION-RECORD.md.' $ColDim 13))
        Add-HelpActions
        return
    }

    $sections = @()
    try { $sections = @(Get-HelpSections -WizardName $WizardName -Version $WizardVersion) }
    catch { Log ("help: {0}" -f $_.Exception.Message); Add-HelpActions; return }

    $first = $true
    foreach ($sec in $sections) {
        $heading = [string]$sec.heading
        if ($heading -ne '') {
            $h = New-Text $heading $ColText 14 $true
            # Tight on purpose. The page has to fit the window without
            # scrolling, and the spacing between sections is most of its
            # height. HelpText.ps1's own test enforces the budget.
            $h.Margin = $(if ($first) { '0,0,0,3' } else { '0,10,0,3' })
            [void]$script:helpPanel.Children.Add($h)
        }
        foreach ($line in @($sec.lines)) {
            $t = New-Text ([string]$line) $ColDim 13
            $t.Margin = '14,0,0,1'
            [void]$script:helpPanel.Children.Add($t)
        }
        $first = $false
    }

    Add-HelpActions
}


function Render-Status {
    $s = $script:uiStatus
    $script:lightsPanel.Children.Clear()
    $script:healthPanel.Children.Clear()
    if ($null -eq $s) {
        [void]$script:lightsPanel.Children.Add((New-Text 'The health check could not run - see wizard.log.' $ColDim 14))
        return
    }
    Render-PlaySummary $s

    foreach ($p in $s.checks.PSObject.Properties) {
        $c = $p.Value

        # Health tab: a card per check with detail and a fix button
        $card = New-Object System.Windows.Controls.Border
        $card.Background = (New-Brush $ColPanel); $card.CornerRadius = '6'
        $card.Padding = '14,10'; $card.Margin = '0,0,0,10'
        $inner = New-Object System.Windows.Controls.StackPanel
        $head = New-Object System.Windows.Controls.StackPanel
        $head.Orientation = 'Horizontal'
        [void]$head.Children.Add((New-StatusLight ([string]$c.status) '0,3,10,0'))
        [void]$head.Children.Add((New-Text ("{0}  -  {1}" -f $c.title, $c.summary) $ColText 14 $true))
        [void]$inner.Children.Add($head)
        foreach ($d in @($c.detail)) {
            $dt = New-Text ([string]$d) $ColDim 13
            $dt.Margin = '22,3,0,0'
            [void]$inner.Children.Add($dt)
        }
        if ($script:fixMap.ContainsKey($p.Name) -and ([string]$c.status) -in @('warn','bad')) {
            $fb = New-Object System.Windows.Controls.Button
            $fb.Content = $script:fixMap[$p.Name][1]; $fb.Padding = '12,5'; $fb.FontSize = 13
            $fb.Margin = '22,8,0,2'; $fb.HorizontalAlignment = 'Left'
            $fb.Tag = $p.Name
            $fb.Add_Click({
                param($s2, $e2)
                $key = [string]$s2.Tag
                if (($script:needsClosed -contains $key) -and (Test-RetroBatRunning)) {
                    [void](Show-Choice $WizardName 'RetroBat is open. Close it completely first - EmulationStation throws away settings changes when it exits.' @('OK'))
                    return
                }
                $script:refreshNote.Text = 'Working...'
                $script:win.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Render)
                [void](Invoke-Step $script:fixMap[$key][0] $script:fixMap[$key][1])
                $script:uiStatus = Invoke-Health
                Render-Status
                $script:refreshNote.Text = 'Done. Details are in wizard.log.'
            })
            [void]$inner.Children.Add($fb)
        }
        $card.Child = $inner
        [void]$script:healthPanel.Children.Add($card)
    }
    $foot = "$($s.machine)"
    if ($s.profile) { $foot += "  |  $($s.profile)" }
    if ($s.tier)    { $foot += "  |  $(([string]$s.tier).ToUpper()) tier" }
    $foot += "  |  overall: $(([string]$s.overall).ToUpper())  |  checked $($s.generated)"
    $script:footer.Text = $foot
}


# ===========================================================================
#  The Machine tab  (Phase 4)
# ---------------------------------------------------------------------------
#  A window over the machine profile system, nothing more. It reads what
#  ProfileEngine.ps1 resolves and, on Apply, writes at most two things into
#  this machine's profile file (the tier line and the [console-tiers]
#  section) and then runs Apply-Settings, which is the same script the
#  Apply My Settings button runs. Every change is still one readable line in
#  a text file afterwards, which is the point.
#
#  NOTHING IS WRITTEN UNTIL "Apply changes" IS PRESSED.
# ===========================================================================

$script:TierNames   = @('low', 'medium', 'high')
$script:choiceCache = @{}
$script:choiceValues = @{}
$script:advancedOpen = $false

function New-SectionHeader([string]$t) {
    $tb = New-Text $t $ColText 15 $true
    $tb.Margin = '0,18,0,4'
    return $tb
}

function New-LabelledRow([string]$label, [string]$value) {
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.Margin = '0,2'
    $l = New-Text $label $ColDim 13; $l.Width = 130
    [void]$row.Children.Add($l)
    [void]$row.Children.Add((New-Text $value $ColText 13))
    return $row
}

# Reads the profile system without writing anything, and takes a copy of the
# two things this tab can change so Undo and the dirty check have something
# to compare against.
function Initialize-Profiles {
    $script:mp = $null
    try { $script:mp = Resolve-MachineProfile -Root $Root -NoWrite }
    catch { Log "machine tab: could not resolve the machine profile: $_" }

    $script:consoles = @()
    try { $script:consoles = @(Get-ProfileConsoles -Root $Root) } catch { }

    $script:origTier         = ''
    $script:origConsoleTiers = @{}
    $script:pendingConsoleTiers = @{}
    $script:origOverrides    = @{}
    $script:pendingOverrides = @{}
    $script:origGameSettings    = @{}
    $script:pendingGameSettings = @{}
    # Controllers are a DRIVE fact, not a profile one: they live in
    # _ClaudeWorkspace\controllers.ini and every computer shares them.
    # Keyed "console|game key", value = kind name. Pending holds only the
    # games changed on this visit; each carries Console, Path, Name, Kind.
    $script:origControllers    = @{}
    $script:pendingControllers = @{}
    if ($script:gameInfoOk) {
        try {
            $asg = Get-ControllerAssignments $Root
            foreach ($c in $asg.Keys) { foreach ($k in $asg[$c].Keys) { $script:origControllers[$c + '|' + $k] = [string]$asg[$c][$k] } }
        }
        catch { Log "machine tab: could not read controllers.ini: $_" }
    }
    $script:advancedBuilt    = $false
    if ($script:mp -and $script:mp.Ok) {
        $script:origTier = [string]$script:mp.Tier
        foreach ($c in $script:consoles) {
            $v = ''
            if ($script:mp.ConsoleTiers -and $script:mp.ConsoleTiers.ContainsKey($c)) {
                $v = [string]$script:mp.ConsoleTiers[$c]
            }
            $script:origConsoleTiers[$c]    = $v
            $script:pendingConsoleTiers[$c] = $v
        }
    }
    $script:pendingTier = $script:origTier

    # The pinned settings are read from the FILE, not from the merged result:
    # a pin can legitimately hold the same value the tier already gives, and
    # the merged result cannot tell those two apart.
    if ($script:mp -and $script:mp.ProfileFile -and (Test-Path -LiteralPath $script:mp.ProfileFile)) {
        $ini = Read-ProfileIni $script:mp.ProfileFile
        if ($ini.Contains('overrides')) {
            foreach ($k in ($ini['overrides']).Keys) {
                $script:origOverrides[$k]    = [string](($ini['overrides'])[$k])
                $script:pendingOverrides[$k] = [string](($ini['overrides'])[$k])
            }
        }
        # Only the profile's OWN per-game lines. The shared ones in
        # machine\game-settings.ini are read by the engine and applied, but
        # they are not this profile's to edit, so the tab never shows them as
        # its own and can never accidentally copy them in here.
        if ($ini.Contains('game-settings')) {
            foreach ($k in ($ini['game-settings']).Keys) {
                $script:origGameSettings[$k]    = [string](($ini['game-settings'])[$k])
                $script:pendingGameSettings[$k] = [string](($ini['game-settings'])[$k])
            }
        }
    }
}

function Update-TierHighlight {
    foreach ($b in @($script:tierButtons)) {
        if ([string]$b.Tag -eq $script:pendingTier) {
            $b.Background = (New-Brush '#FF2FA84F'); $b.Foreground = (New-Brush '#FFFFFFFF')
        }
        else {
            $b.Background = (New-Brush '#FF33333E'); $b.Foreground = (New-Brush $ColText)
        }
    }
}

function Update-ProfileDirty {
    $changes = @()
    if ($script:pendingTier -ne $script:origTier) {
        $changes += "this computer to $($script:pendingTier.ToUpper())"
    }
    foreach ($c in @($script:pendingConsoleTiers.Keys)) {
        $now = [string]$script:pendingConsoleTiers[$c]
        $was = [string]$script:origConsoleTiers[$c]
        if ($now -ne $was) {
            if ($now -eq '') { $changes += "$c back to this computer's tier" }
            else             { $changes += "$c to $($now.ToUpper())" }
        }
    }
    $pinChanges = 0
    foreach ($k in @($script:pendingOverrides.Keys)) {
        if (-not $script:origOverrides.ContainsKey($k)) { $pinChanges++ }
        elseif ([string]$script:pendingOverrides[$k] -ne [string]$script:origOverrides[$k]) { $pinChanges++ }
    }
    foreach ($k in @($script:origOverrides.Keys)) {
        if (-not $script:pendingOverrides.ContainsKey($k)) { $pinChanges++ }
    }
    if ($pinChanges -eq 1) { $changes += '1 individual setting' }
    elseif ($pinChanges -gt 1) { $changes += "$pinChanges individual settings" }

    $gameChanges = 0
    foreach ($k in @($script:pendingGameSettings.Keys)) {
        if (-not $script:origGameSettings.ContainsKey($k)) { $gameChanges++ }
        elseif ([string]$script:pendingGameSettings[$k] -ne [string]$script:origGameSettings[$k]) { $gameChanges++ }
    }
    foreach ($k in @($script:origGameSettings.Keys)) {
        if (-not $script:pendingGameSettings.ContainsKey($k)) { $gameChanges++ }
    }
    if ($gameChanges -eq 1) { $changes += '1 setting for one game' }
    elseif ($gameChanges -gt 1) { $changes += "$gameChanges settings for single games" }

    $ctlChanges = 0
    foreach ($k in @($script:pendingControllers.Keys)) {
        if ([string]$script:pendingControllers[$k].Kind -ne [string]$script:origControllers[$k]) { $ctlChanges++ }
    }
    if ($ctlChanges -eq 1) { $changes += "1 game's controllers" }
    elseif ($ctlChanges -gt 1) { $changes += "$ctlChanges games' controllers" }

    if ($changes.Count -gt 0) {
        $script:profileBarText.Text = ("Not saved yet: " + ($changes -join ', '))
        $script:profileBar.Visibility = 'Visible'
    }
    else {
        $script:profileBar.Visibility = 'Collapsed'
    }
}

function Render-Profiles {
    $script:profileLoading = $true
    $panel = $script:profilePanel
    $panel.Children.Clear()
    $script:tierButtons = @()

    $mp = $script:mp
    if ($null -eq $mp -or -not $mp.Ok) {
        [void]$panel.Children.Add((New-Text 'The machine settings could not be read. Everything else still works - see wizard.log.' $ColDim 14))
        $script:profileBar.Visibility = 'Collapsed'
        $script:profileLoading = $false
        return
    }

    # --- this computer ------------------------------------------------------
    [void]$panel.Children.Add((New-SectionHeader 'This computer'))
    [void]$panel.Children.Add((New-LabelledRow 'Name'          ([string]$mp.Machine)))
    [void]$panel.Children.Add((New-LabelledRow 'Graphics card' ([string]$mp.Gpu)))
    [void]$panel.Children.Add((New-LabelledRow 'Brand rules'   ([string]$mp.Vendor)))
    if ($mp.Created) {
        [void]$panel.Children.Add((New-LabelledRow 'Machine' 'none yet, Apply changes will create one'))
    }
    else {
        [void]$panel.Children.Add((New-LabelledRow 'Machine' ([System.IO.Path]::GetFileNameWithoutExtension([string]$mp.ProfileFile))))
    }
    foreach ($m in @($mp.Messages)) {
        $t = New-Text ([string]$m) '#FFE5B83B' 13
        $t.Margin = '0,6,0,0'
        [void]$panel.Children.Add($t)
    }

    # --- machine tier -------------------------------------------------------
    [void]$panel.Children.Add((New-SectionHeader 'How hard this computer is pushed'))
    [void]$panel.Children.Add((New-Text 'Low favours smoothness, High favours picture quality. This is the starting point for all six consoles.' $ColDim 13))
    $tierRow = New-Object System.Windows.Controls.StackPanel
    $tierRow.Orientation = 'Horizontal'; $tierRow.Margin = '0,10,0,0'
    foreach ($t in $script:TierNames) {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $t.ToUpper(); $b.Width = 110; $b.Height = 34; $b.FontSize = 14
        $b.Margin = '0,0,8,0'; $b.BorderThickness = '0'; $b.Cursor = 'Hand'; $b.Tag = $t
        $b.Add_Click({
            param($s2, $e2)
            $script:pendingTier = [string]$s2.Tag
            Update-TierHighlight
            Update-ProfileDirty
        })
        $script:tierButtons += $b
        [void]$tierRow.Children.Add($b)
    }
    [void]$panel.Children.Add($tierRow)
    Update-TierHighlight

    # --- per-console tiers --------------------------------------------------
    [void]$panel.Children.Add((New-SectionHeader 'One console at a different tier'))
    [void]$panel.Children.Add((New-Text 'For when the computer is fine except for one emulator. Try this before pinning individual settings: it is one line, and that console keeps improving whenever its tier file improves.' $ColDim 13))
    foreach ($c in @($script:consoles)) {
        $row = New-Object System.Windows.Controls.StackPanel
        $row.Orientation = 'Horizontal'; $row.Margin = '0,7,0,0'
        $l = New-Text $c $ColText 13; $l.Width = 130; $l.Margin = '0,5,0,0'
        [void]$row.Children.Add($l)
        $cb = New-Object System.Windows.Controls.ComboBox
        $cb.Width = 210; $cb.FontSize = 13; $cb.Tag = $c
        [void]$cb.Items.Add('same as this computer')
        foreach ($t in $script:TierNames) { [void]$cb.Items.Add($t) }
        $cur = [string]$script:pendingConsoleTiers[$c]
        if ($cur -eq '') { $cb.SelectedIndex = 0 } else { $cb.SelectedItem = $cur }
        $cb.Add_SelectionChanged({
            param($s2, $e2)
            if ($script:profileLoading) { return }
            $v = [string]$s2.SelectedItem
            if ($v -eq 'same as this computer') { $v = '' }
            $script:pendingConsoleTiers[[string]$s2.Tag] = $v
            Update-ProfileDirty
        })
        [void]$row.Children.Add($cb)
        [void]$panel.Children.Add($row)
    }

    # --- advanced: individual settings --------------------------------------
    #  Breath of the Wild's button used to sit out here on the main page. It
    #  moved inside the Advanced section on 2026-09-18: it is one game on one
    #  emulator, and the front of this tab is for the things that affect
    #  everything.
    # Built only when the section is actually opened. Reading es_features.cfg
    # means parsing 1.4 MB of XML, and there is no reason to make the window
    # slow to open for something most visits never touch.
    $exp = New-Object System.Windows.Controls.Expander
    $exp.Margin = '0,22,0,0'; $exp.FontSize = 15
    $exp.Foreground = (New-Brush $ColText)
    $exp.Header = 'Advanced: individual settings, one game at a time, Breath of the Wild'
    $advPanel = New-Object System.Windows.Controls.StackPanel
    $advPanel.Margin = '0,8,0,0'
    $exp.Content = $advPanel
    $script:advancedPanel = $advPanel
    $script:advancedBuilt = $false
    $exp.Add_Expanded({ $script:advancedOpen = $true;  Build-AdvancedEditor })
    $exp.Add_Collapsed({ $script:advancedOpen = $false })
    [void]$panel.Children.Add($exp)
    if ($script:advancedOpen) { $exp.IsExpanded = $true }

    # --- every profile on the drive ------------------------------------------
    #  This used to be a list of "other computers this drive has been plugged
    #  into", with a Delete button and nothing else, which described what the
    #  files ARE rather than what they are FOR. A profile is a set of settings
    #  with a name on it, and the useful things to do with one are: use it,
    #  rename it, throw it away, or start a new one.
    Render-ProfileList $panel

    Update-ProfileDirty
    $script:profileLoading = $false
}

# ===========================================================================
#  THE PROFILE LIST                                   (rebuilt 2026-09-18)
# ===========================================================================
#  A profile is a named set of settings. Four things are worth doing with
#  one, and until now only the last was possible:
#
#      Use this one   run the drive as this profile on whatever computer it
#                     is plugged into. Written to machine\pinned.txt
#      Rename         the 'name =' line and the file, together
#      Delete         moved into _SAFE TO DELETE, never deleted
#      New            an empty profile tied to no computer at all
#
#  THE ICONS. Each profile wears a little pixel controller. Nobody chooses
#  it: Get-ProfileIcon picks the same one every time from the name, so a
#  list of profiles is telling apart at a glance without anybody doing any
#  work. An 'icon =' line in the profile overrules it, which is where a
#  future set of pixel characters would plug in.
#
#  AUTOMATIC IS STILL THE DEFAULT. With no pin, the drive picks the profile
#  matching the computer, exactly as it always has. The pin is a deliberate
#  override and says so, on screen and in machine\pinned.txt.
# ---------------------------------------------------------------------------
function Render-ProfileList($panel) {
    [void]$panel.Children.Add((New-SectionHeader 'Machines on this drive'))

    $pinned = ''
    try { $pinned = Get-PinnedProfile -Root $Root } catch { }

    if ($pinned -ne '') {
        $t = New-Text ("This drive is set to run as '$pinned' on every computer, not just the one it was made for.") '#FFE5B83B' 13
        $t.TextWrapping = 'Wrap'
        [void]$panel.Children.Add($t)
    }
    else {
        [void]$panel.Children.Add((New-Text 'The drive picks the machine that matches whichever computer it is plugged into. Press "Use this one" to make it always use a particular one instead.' $ColDim 13))
    }

    $list = @()
    try { $list = @(Get-ProfileList -Root $Root) } catch { Log "machine tab: could not list profiles - $_" }

    if ($list.Count -eq 0) {
        [void]$panel.Children.Add((New-Text 'No machines saved yet. One is made automatically the first time the drive is used on a computer.' $ColDim 13))
    }

    foreach ($p in $list) {
        $row = New-Object System.Windows.Controls.StackPanel
        $row.Orientation = 'Horizontal'; $row.Margin = '0,9,0,0'

        # The little controller. Optional like every picture here: no
        # wizard\profile-*.png and the row simply has no picture.
        $img = New-Object System.Windows.Controls.Image
        $bmp = Get-PixelBitmap (Join-Path $WizardDir ('profile-' + [string]$p.Icon + '.png'))
        if ($null -ne $bmp) { $img.Source = $bmp }
        $img.Stretch = 'None'
        $img.Width = 50; $img.Height = 42
        $img.Margin = '0,0,12,0'; $img.VerticalAlignment = 'Center'
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, [System.Windows.Media.BitmapScalingMode]::NearestNeighbor)
        [void]$row.Children.Add($img)

        $col = New-Object System.Windows.Controls.StackPanel
        $col.Width = 250; $col.VerticalAlignment = 'Center'
        $nm = New-Text ([string]$p.Name) $ColText 14 $true
        [void]$col.Children.Add($nm)

        $bits = @(("{0} tier" -f $p.Tier))
        if ($p.IsThisComputer) { $bits += 'this computer' }
        if ($p.IsInUse)        { $bits += 'IN USE' }
        if (-not $p.IsThisComputer -and [string]$p.Machine -ne '') { $bits += ("made for {0}" -f $p.Machine) }
        $sub = New-Text ($bits -join '  -  ') $ColDim 12
        [void]$col.Children.Add($sub)
        [void]$row.Children.Add($col)

        $useBtn = New-Object System.Windows.Controls.Button
        $useBtn.Content = 'Use this one'; $useBtn.Padding = '10,4'; $useBtn.FontSize = 13
        $useBtn.Margin = '0,0,6,0'; $useBtn.VerticalAlignment = 'Center'
        $useBtn.Tag = [string]$p.Name
        $useBtn.IsEnabled = (-not $p.IsInUse)
        $useBtn.Add_Click({ param($s2, $e2) Invoke-ProfileUse ([string]$s2.Tag) })
        [void]$row.Children.Add($useBtn)

        $renBtn = New-Object System.Windows.Controls.Button
        $renBtn.Content = 'Rename'; $renBtn.Padding = '10,4'; $renBtn.FontSize = 13
        $renBtn.ToolTip = 'Change its name, and pick its picture'
        $renBtn.Margin = '0,0,6,0'; $renBtn.VerticalAlignment = 'Center'
        $renBtn.Tag = [string]$p.File
        $renBtn.Add_Click({ param($s2, $e2) Invoke-ProfileRename ([string]$s2.Tag) })
        [void]$row.Children.Add($renBtn)

        $delBtn = New-Object System.Windows.Controls.Button
        $delBtn.Content = 'Delete'; $delBtn.Padding = '10,4'; $delBtn.FontSize = 13
        $delBtn.VerticalAlignment = 'Center'
        $delBtn.Tag = [string]$p.File
        $delBtn.Add_Click({ param($s2, $e2) Invoke-ProfileDelete ([string]$s2.Tag) })
        [void]$row.Children.Add($delBtn)

        [void]$panel.Children.Add($row)
    }

    $btnRow = New-Object System.Windows.Controls.StackPanel
    $btnRow.Orientation = 'Horizontal'; $btnRow.Margin = '0,16,0,0'

    $newBtn = New-Object System.Windows.Controls.Button
    $newBtn.Content = 'Make a new machine'; $newBtn.Padding = '14,6'; $newBtn.FontSize = 14
    $newBtn.Margin = '0,0,8,0'
    $newBtn.Add_Click({ Invoke-ProfileNew })
    [void]$btnRow.Children.Add($newBtn)

    if ($pinned -ne '') {
        $autoBtn = New-Object System.Windows.Controls.Button
        $autoBtn.Content = 'Go back to automatic'; $autoBtn.Padding = '14,6'; $autoBtn.FontSize = 14
        $autoBtn.Add_Click({ Invoke-ProfileUse '' })
        [void]$btnRow.Children.Add($autoBtn)
    }
    [void]$panel.Children.Add($btnRow)

    # Steam belongs on THIS tab because it is exactly what this tab is for: a
    # setting that lives in this computer's profile rather than on the drive.
    if ($script:steamOk) { Add-SteamSection $panel }
}

# ===========================================================================
#  STEAM ON THIS COMPUTER   (Machine tab, added 2026-09-19)
# ===========================================================================
#  Why here and not on Features: features.ini is ONE file shared by every
#  computer the drive is ever plugged into, so a switch there would follow
#  the drive to a friend's PC and offer them games they cannot play. The
#  [steam] section lives in machine\machines\<name>.ini instead, which is
#  per computer, which is the whole point.
#
#  Both buttons open windows that live in scripts\SteamUI.ps1, so the wizard
#  holds no Steam logic of its own and both are still reachable from
#  Maintenance Steps\Connect Steam.bat if this window ever breaks.
# ---------------------------------------------------------------------------
function Add-SteamSection($panel) {
    if (-not $script:steamOk) { return }

    try {
        $sep = New-Object System.Windows.Controls.Border
        $sep.Height = 1
        $sep.Background = (New-Brush '#FF3A3A46')
        $sep.Margin = '0,22,0,16'
        [void]$panel.Children.Add($sep)

        $h = New-Text 'Steam on this computer' $ColText 16 $true
        $h.Margin = '0,0,0,6'
        [void]$panel.Children.Add($h)

        $state = Get-SteamProfileState -Root $Root
        $games = @()
        try { $games = @(Get-SteamWantedGames -Root $Root) } catch { }

        if ($state.Connected) {
            $who = ''
            if ([string]$state.Account -ne '') { $who = ' as ' + [string]$state.Account }
            $whose = ''
            if ($state.Mode -eq 'guest')     { $whose = ' Showing games downloaded on this computer.' }
            elseif ($state.Mode -eq 'owner') { $whose = ' Showing games from the drive and this computer.' }
            $line = ('Connected' + $who + '.' + $whose + ' ' + $games.Count + ' Steam game(s) in RetroBat here.')
            $s1 = New-Text $line $ColText 14
            $s1.MaxWidth = 560
        }
        else {
            $s1 = New-Text 'Not connected here, so no Steam games show in RetroBat on this computer.' $ColText 14
        }
        $s1.Margin = '0,0,0,4'
        [void]$panel.Children.Add($s1)

        $s2 = New-Text 'Remembered per computer. A friend can set it up with their own Steam account to show their own couch games while the drive is at their place. Plug the drive into a different computer and Steam games stay hidden there until Steam setup is run on it.' $ColDim 13
        $s2.Margin = '0,0,0,12'
        $s2.MaxWidth = 560
        [void]$panel.Children.Add($s2)

        $row = New-Object System.Windows.Controls.StackPanel
        $row.Orientation = 'Horizontal'

        $cb = New-Object System.Windows.Controls.Button
        $cb.Padding = '14,6'; $cb.FontSize = 14; $cb.Margin = '0,0,8,0'
        if ($state.Connected) { $cb.Content = 'Change Steam games' } else { $cb.Content = 'Set up Steam' }
        $cb.Add_Click({ Invoke-ConnectSteamFromWizard })
        [void]$row.Children.Add($cb)

        if ($state.Connected) {
            $db = New-Object System.Windows.Controls.Button
            $db.Content = 'Disconnect Steam from this hard drive'
            $db.Padding = '14,6'; $db.FontSize = 14
            $db.Add_Click({ Invoke-DisconnectSteamFromWizard })
            [void]$row.Children.Add($db)
        }

        [void]$panel.Children.Add($row)
    }
    catch { Log ('steam section: ' + $_.Exception.Message) }
}

# RetroBat has to be shut first: it only reads its game lists when it starts,
# so tiles added underneath a running RetroBat would not appear until it was
# closed and opened again, and that confusion costs more than the wait.
function Test-SteamCanRun {
    if (Test-RetroBatRunning) {
        [void](Show-Choice $WizardName "Close RetroBat first.`n`nRetroBat only reads its game list when it starts, so anything added now would not show up until it was closed and opened again." @('OK'))
        return $false
    }
    return $true
}

function Invoke-ConnectSteamFromWizard {
    if (-not $script:steamOk) { return }
    if (-not (Test-SteamCanRun)) { return }
    try {
        $r = Show-ConnectSteamWindow -Root $Root
        Log ('steam: connect window returned ' + $r)
    }
    catch { Log ('steam: connect window failed - ' + $_.Exception.Message) }
    Render-Profiles
}

function Invoke-ShortcutMakerFromWizard {
    if (-not $script:shortcutMakerOk) { return }
    try {
        $r = Show-ShortcutMakerWindow -Root $Root -StartMenuFolder ($WizardName + ' Games')
        Log ('shortcut maker returned ' + $r)
    }
    catch { Log ('shortcut maker failed - ' + $_.Exception.Message) }
}

# The same offer as the setup flow, for anyone who came looking.
function Invoke-DriveLetterFromWizard {
    if (-not $script:driveLetterOk) { return }
    try {
        $dls = Get-DriveLetterStatus -Root $Root
        if ($dls.State -ne 'canchange' -and $dls.State -ne 'needsadmin') {
            [void](Show-Choice $WizardName $dls.Line @('OK'))
            Render-Help
            return
        }

        $pick = Show-Choice $WizardName ($dls.Line + "`n`nNothing on this drive needs R: - everything works out where it is by itself. This is a safety net for the odd setting inside an emulator that insists on a letter.`n`nAnything you have open from the drive should be closed first. Windows will ask for permission - say Yes.") @('Yes, use R:', 'Cancel')
        if ($pick -ne 'Yes, use R:') { return }

        $r = Invoke-DriveLetterMove

        if ($r.Changed) {
            [void](Show-Choice $WizardName ($r.Message + $r.Extra + "`n`nThis window will now reopen itself from the new letter.") @('OK'))
            Restart-WizardFrom -NewRoot $r.NewRoot
            try { $script:win.Close() } catch { }
            return
        }
        [void](Show-Choice $WizardName $r.Message @('OK'))
        Render-Help
    }
    catch { Log ('drive letter button failed - ' + $_.Exception.Message) }
}

function Invoke-DisconnectSteamFromWizard {
    if (-not $script:steamOk) { return }
    if (-not (Test-SteamCanRun)) { return }
    try {
        $r = Show-DisconnectSteamWindow -Root $Root
        Log ('steam: disconnect window returned ' + $r)
    }
    catch { Log ('steam: disconnect window failed - ' + $_.Exception.Message) }
    Render-Profiles
}


# Choosing a profile only changes which settings the drive WANTS. Applying
# them is a separate, slower thing that needs RetroBat closed, so it is
# offered rather than assumed - and saying "later" still leaves the choice
# saved, which is why this never half-does anything.
function Invoke-ProfileUse([string]$Name) {
    if ($Name -eq '') {
        $pick = Show-Choice $WizardName "Go back to picking the machine that matches the computer?`n`nNothing is deleted. Every machine stays exactly where it is." @('Go automatic', 'Cancel')
        if ($pick -ne 'Go automatic') { return }
    }
    if (-not (Set-PinnedProfile -Root $Root -Name $Name)) {
        [void](Show-Choice $WizardName 'That could not be saved. The details are in wizard.log.' @('OK'))
        Log "machine tab: could not write the pin for '$Name'"
        return
    }
    Log ("machine tab: pinned profile set to '{0}'" -f $(if ($Name -eq '') { '(automatic)' } else { $Name }))

    $what = if ($Name -eq '') { 'this computer''s own settings' } else { "the '$Name' machine" }
    $pick = Show-Choice $WizardName ("Saved. The drive will use $what.`n`nApply it now? That rewrites the emulator settings and needs RetroBat closed. Choosing Later changes nothing today - it is applied the next time settings are applied.") @('Apply now', 'Later')

    if ($pick -eq 'Apply now') {
        if (Test-RetroBatRunning) {
            $c = Show-Choice $WizardName 'RetroBat is open. It rewrites its settings when it closes, so anything applied now would be thrown away.' @('Close RetroBat', 'Later')
            if ($c -ne 'Close RetroBat') { $pick = 'Later' } else { Close-RetroBat }
        }
    }
    if ($pick -eq 'Apply now') {
        $code = Invoke-Step 'Apply-Settings.ps1' 'applying the chosen machine'
        if ($code -ne 0) {
            [void](Show-Choice $WizardName 'That did not finish. Nothing was left half-done; the details are in wizard.log.' @('OK'))
        }
        $script:uiStatus = Invoke-Health
        Render-Status
    }

    Initialize-Profiles
    Render-Profiles
}


function Invoke-ProfileRename([string]$File) {
    if (-not (Test-Path -LiteralPath $File)) { return }
    $old     = [System.IO.Path]::GetFileNameWithoutExtension($File)
    $oldIcon = ''
    try {
        $ini = Read-ProfileIni $File
        if ($ini.Contains('profile')) {
            if (($ini['profile']).Contains('name')) { $old     = [string](($ini['profile'])['name']) }
            if (($ini['profile']).Contains('icon')) { $oldIcon = [string](($ini['profile'])['icon']) }
        }
    } catch { }

    $ans = Show-ProfileEditor $WizardName $old $oldIcon
    if (-not $ans.Ok) { return }
    $new     = [string]$ans.Name
    $newIcon = [string]$ans.Icon

    if ($new -ne $old) {
        $res = Rename-ProfileFile -Root $Root -File $File -NewName $new
        if ($res -eq '') {
            [void](Show-Choice $WizardName ("That name could not be used.`n`nEither a machine is already called that, or the name has characters Windows will not put in a file name.") @('OK'))
            return
        }
        Log "machine tab: renamed '$old' to '$new'"
        $File = $res
    }

    if ($newIcon -ne $oldIcon) {
        if (Set-ProfileIcon -File $File -Icon $newIcon) {
            Log ("machine tab: '{0}' picture set to '{1}'" -f $new, $(if ($newIcon -eq '') { 'automatic' } else { $newIcon }))
        }
        else { Log "machine tab: could not write the picture into $File" }
    }

    Initialize-Profiles
    Render-Profiles
}


# ===========================================================================
#  NAMING A PROFILE, AND GIVING IT A FACE
# ===========================================================================
#  One box for the name and a row of pictures to pick from. It replaced a
#  plain text prompt because a list of profiles is read by its pictures long
#  before it is read by its words, and having no say in the picture made the
#  list feel like it belonged to the drive rather than to Steven.
#
#  "Let the name choose" is kept as a real option and is the default, so a
#  profile nobody has thought about still looks deliberate.
#
#  Same script-scope rule as every other dialog here: an event handler in
#  Windows PowerShell cannot be relied on to see a function's own variables.
# ---------------------------------------------------------------------------
$script:iconButtons = @()

function Show-ProfileEditor([string]$Title, [string]$Name, [string]$Icon) {
    Close-Splash

    $w = New-Object System.Windows.Window
    $w.Title = $Title; $w.Width = 560; $w.SizeToContent = 'Height'
    $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'NoResize'
    $w.Background = (New-Brush $ColBg); $w.Topmost = $true

    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = '22'

    [void]$sp.Children.Add((New-Text 'Name' $ColText 15 $true))
    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Text = $Name; $tb.FontSize = 15; $tb.Margin = '0,6,0,0'; $tb.Padding = '4,3'
    [void]$sp.Children.Add($tb)

    $h = New-Text 'Picture' $ColText 15 $true
    $h.Margin = '0,18,0,0'
    [void]$sp.Children.Add($h)
    [void]$sp.Children.Add((New-Text 'Only how it looks in the list. It changes nothing about how the drive runs.' $ColDim 12))

    $wrap = New-Object System.Windows.Controls.WrapPanel
    $wrap.Margin = '0,10,0,0'
    $script:iconButtons = @()

    # "Let the name choose" first, as a word rather than a picture, because
    # that is what it is - the absence of a choice.
    $auto = New-Object System.Windows.Controls.Button
    $auto.Content = 'Let the name choose'
    $auto.Tag = ''; $auto.Padding = '10,6'; $auto.FontSize = 12
    $auto.Margin = '0,0,8,8'; $auto.Cursor = 'Hand'
    $auto.Add_Click({ param($s2, $e2) Select-ProfileIconButton ([string]$s2.Tag) })
    $script:iconButtons += $auto
    [void]$wrap.Children.Add($auto)

    foreach ($n in $script:ProfileIconChoices) {
        $b = New-Object System.Windows.Controls.Button
        $b.Tag = $n; $b.Margin = '0,0,8,8'; $b.Cursor = 'Hand'
        $b.Width = 68; $b.Height = 60; $b.ToolTip = $n
        $bmp = Get-PixelBitmap (Join-Path $WizardDir ('profile-' + $n + '.png'))
        if ($null -eq $bmp) { continue }
        $img = New-Object System.Windows.Controls.Image
        $img.Source = $bmp; $img.Stretch = 'None'
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, [System.Windows.Media.BitmapScalingMode]::NearestNeighbor)
        $b.Content = $img
        $b.Add_Click({ param($s2, $e2) Select-ProfileIconButton ([string]$s2.Tag) })
        $script:iconButtons += $b
        [void]$wrap.Children.Add($b)
    }
    [void]$sp.Children.Add($wrap)

    $script:profEditName = $tb
    $script:profEditIcon = ([string]$Icon).Trim().ToLower()
    $script:profEditOk   = $false
    $script:profEditWin  = $w
    Select-ProfileIconButton $script:profEditIcon

    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.HorizontalAlignment = 'Right'; $row.Margin = '0,10,0,0'
    $cancel = New-Object System.Windows.Controls.Button
    $cancel.Content = 'Cancel'; $cancel.Padding = '16,7'; $cancel.FontSize = 14
    $cancel.Add_Click({ $script:profEditOk = $false; $script:profEditWin.Close() })
    $save = New-Object System.Windows.Controls.Button
    $save.Content = 'Save'; $save.Padding = '16,7'; $save.FontSize = 14; $save.Margin = '8,0,0,0'
    $save.Add_Click({ $script:profEditOk = $true; $script:profEditWin.Close() })
    [void]$row.Children.Add($cancel)
    [void]$row.Children.Add($save)
    [void]$sp.Children.Add($row)

    $w.Content = $sp
    [void]$w.ShowDialog()

    $out = @{ Ok = $script:profEditOk; Name = ([string]$script:profEditName.Text).Trim(); Icon = $script:profEditIcon }
    if ($out.Name -eq '') { $out.Ok = $false }
    return $out
}

# Remembers the choice and shows which one it is. Top level, not a closure,
# because every one of those buttons has to be able to find it.
function Select-ProfileIconButton([string]$Icon) {
    $script:profEditIcon = ([string]$Icon).Trim().ToLower()
    foreach ($b in @($script:iconButtons)) {
        if ([string]$b.Tag -eq $script:profEditIcon) {
            $b.BorderBrush     = (New-Brush '#FF2FA84F')
            $b.BorderThickness = '3'
            $b.Background      = (New-Brush '#FF2A3A2E')
        }
        else {
            $b.BorderBrush     = (New-Brush '#FF3A3A48')
            $b.BorderThickness = '1'
            $b.Background      = (New-Brush '#FF33333E')
        }
    }
}


# NOTHING ON THIS DRIVE IS DELETED. The file is moved into _SAFE TO DELETE
# with the date on it, which is the same rule the shortcuts, the protected
# files and the old .bat files all follow.
function Invoke-ProfileDelete([string]$File) {
    if (-not (Test-Path -LiteralPath $File)) { return }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($File)

    $extra = ''
    try {
        if ((Get-PinnedProfile -Root $Root) -ieq $name) {
            $extra = "`n`nThis is the machine the drive is set to use, so it will go back to picking the one that matches the computer."
        }
    } catch { }

    $pick = Show-Choice $WizardName ("Throw away the '$name' machine?$extra`n`nNothing on this computer changes. The file is moved into _ClaudeWorkspace\_SAFE TO DELETE, not deleted, and a computer whose machine this was simply gets a fresh one next time.") @('Throw it away', 'Keep it')
    if ($pick -ne 'Throw it away') { return }

    try {
        $bin = Join-Path $Ws '_SAFE TO DELETE'
        if (-not (Test-Path -LiteralPath $bin)) { New-Item -ItemType Directory -Path $bin -Force | Out-Null }
        $dest = Join-Path $bin ("{0}_{1}.ini" -f $name, (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
        Move-Item -LiteralPath $File -Destination $dest -Force
        Log "machine tab: moved profile '$name' into _SAFE TO DELETE"
        if ((Get-PinnedProfile -Root $Root) -ieq $name) { [void](Set-PinnedProfile -Root $Root -Name '') }
    }
    catch {
        Log "machine tab: could not move $File - $_"
        [void](Show-Choice $WizardName 'That could not be moved. The details are in wizard.log.' @('OK'))
    }
    Initialize-Profiles
    Render-Profiles
}


function Invoke-ProfileNew {
    $name = Show-TextInput $WizardName "A name for the new machine.`n`nIt starts empty, belongs to no particular computer, and is used when you press 'Use this one' next to it." 'My settings'
    if ($name -eq '') { return }

    $tier = Show-Choice $WizardName "What should '$name' start from?`n`nLow favours smoothness, High favours picture quality. It can be changed at the top of this tab afterwards." @('Low', 'Medium', 'High')
    if ($tier -eq '') { return }

    $file = New-BlankProfile -Root $Root -Name $name -Tier $tier.ToLower()
    if ($file -eq '') {
        [void](Show-Choice $WizardName ("That name could not be used.`n`nEither a machine is already called that, or the name has characters Windows will not put in a file name.") @('OK'))
        return
    }
    Log "machine tab: made a new profile '$name' ($tier)"
    [void](Show-Choice $WizardName ("'$name' is ready.`n`nIt is not in use yet - press 'Use this one' next to it when you want the drive to run as it.") @('OK'))
    Initialize-Profiles
    Render-Profiles
}


# --- writing the two things this tab can change ----------------------------

# Replaces the [console-tiers] section's settings while keeping its comments.
# Comments matter here: they are what makes the file readable to whoever ends
# up owning this drive.
function Set-ProfileConsoleTiers([string]$ProfileFile, [hashtable]$Tiers) {
    $lines = @([System.IO.File]::ReadAllLines($ProfileFile))
    $wanted = New-Object System.Collections.Generic.List[string]
    foreach ($c in ($Tiers.Keys | Sort-Object)) {
        $v = [string]$Tiers[$c]
        if ($v -ne '') { $wanted.Add(("{0,-9}= {1}" -f $c, $v)) }
    }

    $out = New-Object System.Collections.Generic.List[string]
    $inSection = $false
    $found     = $false
    foreach ($line in $lines) {
        $t = $line.Trim()
        if ($t.StartsWith('[') -and $t.EndsWith(']')) {
            if ($inSection) {
                # Trim any blank lines the section ended with BEFORE adding the
                # new ones, otherwise every save leaves one more blank line
                # behind than the last, and after a month of tinkering the file
                # is mostly empty space.
                while ($out.Count -gt 0 -and $out[$out.Count - 1].Trim() -eq '') { $out.RemoveAt($out.Count - 1) }
                foreach ($w in $wanted) { $out.Add($w) }
                $out.Add('')
            }
            $inSection = ($t -ieq '[console-tiers]')
            if ($inSection) { $found = $true }
            $out.Add($line)
            continue
        }
        if ($inSection) {
            # keep the comments and blank lines, drop the old settings
            if ($t -eq '' -or $t.StartsWith(';') -or $t.StartsWith('#')) { $out.Add($line) }
            continue
        }
        $out.Add($line)
    }
    if ($inSection) {
        while ($out.Count -gt 0 -and $out[$out.Count - 1].Trim() -eq '') { $out.RemoveAt($out.Count - 1) }
        foreach ($w in $wanted) { $out.Add($w) }
    }
    elseif (-not $found) {
        $out.Add('')
        $out.Add('[console-tiers]')
        $out.Add('; One console running at a different tier from the rest of this machine.')
        $out.Add(';   example:  wii = low')
        foreach ($w in $wanted) { $out.Add($w) }
    }
    [System.IO.File]::WriteAllLines($ProfileFile, $out, (New-Object System.Text.UTF8Encoding($false)))
}

# Asks RetroBat to close, politely first, and only forces it after ten
# seconds. Letting EmulationStation shut down normally is deliberate: it
# writes its settings file on the way out, and we want that write to happen
# BEFORE we apply, not after.
function Close-RetroBat {
    Log 'closing RetroBat at the user request'
    foreach ($p in @(Get-Process -Name 'emulationstation', 'RetroBat', 'BatGui' -ErrorAction SilentlyContinue)) {
        try { [void]$p.CloseMainWindow() } catch { }
    }
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        if (-not (Test-RetroBatRunning)) { Log 'RetroBat closed'; return }
    }
    foreach ($p in @(Get-Process -Name 'emulationstation', 'RetroBat', 'BatGui' -ErrorAction SilentlyContinue)) {
        try { $p.Kill(); Log ("had to force " + $p.ProcessName) } catch { }
    }
    Start-Sleep -Milliseconds 800
}

function Invoke-ProfileApply {
    if (Test-RetroBatRunning) {
        $pick = Show-Choice $WizardName "RetroBat is open.`n`nEmulationStation rewrites its settings file when it closes, so anything applied now would be thrown away a few minutes later." @('Close RetroBat for me', 'Cancel')
        if ($pick -ne 'Close RetroBat for me') { return }
        Close-RetroBat
        if (Test-RetroBatRunning) {
            [void](Show-Choice $WizardName 'RetroBat is still open. Close it yourself, then press Apply changes again.' @('OK'))
            return
        }
    }

    $script:profileBarText.Text = 'Working...'
    $script:win.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Render)

    # A machine seen for the first time has no profile file yet, because the
    # tab resolves everything read-only. Apply-Settings is what creates it.
    $file = [string]$script:mp.ProfileFile
    if (-not (Test-Path -LiteralPath $file)) {
        Log 'machine tab: no profile file yet, creating it first'
        [void](Invoke-Step 'Apply-Settings.ps1' 'creating this machine')
        try { $script:mp = Resolve-MachineProfile -Root $Root -NoWrite } catch { }
        $file = [string]$script:mp.ProfileFile
    }

    if (Test-Path -LiteralPath $file) {
        try {
            Set-ProfileTier $file $script:pendingTier
            Set-ProfileConsoleTiers $file $script:pendingConsoleTiers
            Set-ProfileOverrides $file $script:pendingOverrides
            Set-ProfileOverrides -ProfileFile $file -Pins $script:pendingGameSettings `
                -Section 'game-settings' `
                -Header '; One setting for ONE game, on this machine only. See docs\PER-GAME-SETTINGS.md.'
            # Log the whole resulting state, not just what changed. Six months
            # from now the useful question is "what was this machine set to",
            # and a log that only records deltas cannot answer it.
            $ctText = (($script:pendingConsoleTiers.GetEnumerator() | Where-Object { $_.Value -ne '' } |
                        ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ')
            if ($ctText -eq '') { $ctText = 'none' }
            $pinText = (($script:pendingOverrides.GetEnumerator() | Sort-Object Key |
                         ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ')
            if ($pinText -eq '') { $pinText = 'none' }
            $gsText = (($script:pendingGameSettings.GetEnumerator() | Sort-Object Key |
                        ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' | ')
            if ($gsText -eq '') { $gsText = 'none' }
            Log ("profiles tab applied: tier = {0} | console tiers: {1} | pinned: {2}" -f $script:pendingTier, $ctText, $pinText)
            Log ("profiles tab applied: single games: {0}" -f $gsText)
        }
        catch {
            Log "machine tab: could not write $file : $_"
            [void](Show-Choice $WizardName "The machine file could not be written.`n`nDetails are in wizard.log." @('OK'))
            return
        }
    }
    else {
        Log 'machine tab: still no profile file after Apply-Settings, giving up'
        [void](Show-Choice $WizardName "This machine's file could not be created. See wizard.log." @('OK'))
        return
    }

    # Controllers: written to controllers.ini (the whole drive), then the same
    # sync PLAY runs, which updates the menu descriptions and the Wii U
    # block in machine\game-settings.ini. Apply-Settings below applies it.
    $ctl = @()
    foreach ($k in @($script:pendingControllers.Keys)) {
        $pc = $script:pendingControllers[$k]
        if ([string]$pc.Kind -ne [string]$script:origControllers[$k]) { $ctl += $pc }
    }
    if ($ctl.Count -gt 0 -and $script:gameInfoOk) {
        try {
            Set-ControllerKinds $Root $ctl
            Log ("profiles tab applied: controllers: " + (($ctl | ForEach-Object { "$($_.Console) $($_.Name) = $($_.Kind)" }) -join ' | '))
            $gi = Invoke-GameInfoSync -Root $Root
            foreach ($m in @($gi.Messages)) { Log ('game lists: ' + $m) }
        }
        catch {
            Log "machine tab: could not write controllers.ini : $_"
            [void](Show-Choice $WizardName "The controller choice could not be saved.`n`nDetails are in wizard.log." @('OK'))
        }
    }

    [void](Invoke-Step 'Apply-Settings.ps1' 'applying the new machine')
    Initialize-Profiles
    Render-Profiles
    $script:uiStatus = Invoke-Health
    Render-Status
    $script:profileBar.Visibility = 'Collapsed'
    $script:refreshNote.Text = 'Settings applied. Details are in wizard.log.'
}


# ===========================================================================
#  The Features tab  (Phase 6)
# ---------------------------------------------------------------------------
#  A window over _ClaudeWorkspace\features.ini, nothing more. Every switch it
#  shows can be set by editing that file by hand, and Maintenance Steps\Show
#  My Features.bat lists the same thing without a window, because the window
#  is a convenience layer and never a dependency.
#
#  NOTHING IS WRITTEN UNTIL "Apply changes" IS PRESSED.
#
#  Two kinds of switch, and the difference decides what Apply has to do:
#
#    reverts = $true   the change is already sitting in one of RetroBat's own
#                      files, so switching it off has to UNDO it. Apply runs
#                      the script that owns it, and that needs RetroBat closed
#    reverts = $false  the switch only decides whether a step does its work
#                      next time it runs. Apply writes the file and stops.
#                      Nothing to undo, nothing to close
# ===========================================================================

$script:featCat        = $null
$script:featOrig       = @{}
$script:featPending    = @{}
$script:featDescBlocks = @{}

function Initialize-FeatureTab {
    $script:featOrig       = @{}
    $script:featPending    = @{}
    $script:featDescBlocks = @{}
    if (-not $script:featuresOk) { return }

    $script:featCat = Get-FeatureCatalogue
    $vals = Get-Features $Root
    foreach ($k in $script:featCat.Keys) {
        $script:featOrig[$k]    = [bool]$vals[$k]
        $script:featPending[$k] = [bool]$vals[$k]
    }
}

function Update-FeatureDirty {
    $changes = @()
    foreach ($k in @($script:featPending.Keys)) {
        if ([bool]$script:featPending[$k] -ne [bool]$script:featOrig[$k]) {
            $word = if ([bool]$script:featPending[$k]) { 'on' } else { 'off' }
            $changes += ("{0} {1}" -f $script:featCat[$k].title, $word)
        }
    }

    if ($changes.Count -gt 0) {
        $script:featureBarText.Text = ("Not saved yet: " + ($changes -join ', '))
        $script:featureBar.Visibility = 'Visible'
    }
    else {
        $script:featureBar.Visibility = 'Collapsed'
    }
}

# The line under a switch says what it is doing FOR you when it is on, and
# what you are giving up when it is off. One line either way.
function Update-FeatureDesc([string]$Key) {
    if (-not $script:featDescBlocks.ContainsKey($Key)) { return }
    $on = [bool]$script:featPending[$Key]
    $tb = $script:featDescBlocks[$Key]
    if ($on) {
        $tb.Text = [string]$script:featCat[$Key].desc
        $tb.Foreground = (New-Brush $ColDim)
    }
    else {
        $tb.Text = [string]$script:featCat[$Key].off
        $tb.Foreground = (New-Brush '#FFE5B83B')
    }
}

function Update-PadDesc([bool]$on) {
    if ($null -eq $script:padDesc) { return }
    if ($on) {
        $script:padDesc.Text = 'On. SELECT + START on any controller opens this wizard full screen, whenever no game or RetroBat menu is open. Changes straight away - no Apply needed.'
        $script:padDesc.Foreground = (New-Brush $ColDim)
    }
    else {
        $script:padDesc.Text = 'Off on this computer. Tick it to turn it on - it changes straight away, no Apply needed.'
        $script:padDesc.Foreground = (New-Brush '#FFE5B83B')
    }
}

function Render-Features {
    $panel = $script:featurePanel
    $panel.Children.Clear()
    $script:featDescBlocks = @{}

    if (-not $script:featuresOk) {
        $t = New-Text 'Features.ps1 is missing, so nothing can be switched here.' $ColDim 14
        $t.Margin = '0,20,0,0'
        [void]$panel.Children.Add($t)
        [void]$panel.Children.Add((New-Text 'Everything stays on, which is the safe answer.' $ColDim 13))
        return
    }

    [void]$panel.Children.Add((New-SectionHeader 'What this drive does for you'))
    $intro = New-Text 'Untick one to switch it off. Nothing changes until Apply.' $ColDim 13
    $intro.Margin = '0,0,0,6'
    [void]$panel.Children.Add($intro)

    foreach ($k in $script:featCat.Keys) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content    = [string]$script:featCat[$k].title
        $cb.Foreground = (New-Brush $ColText)
        $cb.FontSize   = 14
        $cb.Margin     = '0,14,0,0'
        $cb.Cursor     = 'Hand'
        $cb.IsChecked  = [bool]$script:featPending[$k]

        # The KEY goes in the Tag, and the handler reads it back from $this.
        # A scriptblock built in a loop does not capture $k, it looks $k up
        # when it runs - by which time $k is the last one in the list and
        # every box would edit the same switch.
        $cb.Tag = $k
        $cb.Add_Click({
            $key = [string]$this.Tag
            $want = [bool]$this.IsChecked

            # A switch that can cost somebody something says so BEFORE the
            # box changes, not in a summary afterwards. Only 'savebackup'
            # carries one today. Warn on the way OFF only - turning a
            # protection back on never needs a confirmation.
            if (-not $want -and $script:featCat[$key].ContainsKey('warn')) {
                $pick = Show-Choice $WizardName ([string]$script:featCat[$key].warn) @('Keep it on', 'Turn it off')
                if ($pick -ne 'Turn it off') {
                    # Putting the tick back does NOT fire this handler again:
                    # Click is raised by the user, not by setting IsChecked.
                    $this.IsChecked = $true
                    return
                }
            }

            $script:featPending[$key] = $want
            Update-FeatureDesc $key
            Update-FeatureDirty
        })
        [void]$panel.Children.Add($cb)

        $t = New-Text '' $ColDim 13
        $t.Margin = '25,2,0,0'
        $t.TextWrapping = 'Wrap'
        [void]$panel.Children.Add($t)
        $script:featDescBlocks[$k] = $t
        Update-FeatureDesc $k
    }

    # The controller shortcut is not in features.ini because it is not a
    # setting of the DRIVE - it is something on this one computer. So it
    # works straight away, with no Apply, and every computer has its own.
    if ($script:padShortcutOk) {
        [void]$panel.Children.Add((New-SectionHeader 'On this computer only'))
        $pcb = New-Object System.Windows.Controls.CheckBox
        $pcb.Content    = 'Open the wizard with a controller (SELECT + START)'
        $pcb.Foreground = (New-Brush $ColText)
        $pcb.FontSize   = 14
        $pcb.Margin     = '0,8,0,0'
        $pcb.Cursor     = 'Hand'
        $padOnNow = $false
        try { $padOnNow = [bool](Test-PadShortcutOn) } catch { }
        $pcb.IsChecked  = $padOnNow
        [void]$panel.Children.Add($pcb)
        $script:padDesc = New-Text '' $ColDim 13
        $script:padDesc.Margin = '25,2,0,0'
        $script:padDesc.TextWrapping = 'Wrap'
        [void]$panel.Children.Add($script:padDesc)
        Update-PadDesc $padOnNow
        $pcb.Add_Click({
            $want = [bool]$this.IsChecked
            if ($want) { [void](Install-PadShortcut -Root $Root -Logger { param($m) Log $m }) }
            else       { [void](Remove-PadShortcut -Logger { param($m) Log $m }) }
            $on = $false
            try { $on = [bool](Test-PadShortcutOn) } catch { }
            $this.IsChecked = $on
            Update-PadDesc $on
        })
    }

    $foot = New-Text 'The same switches live in _ClaudeWorkspace\features.ini, and Show My Features.bat lists them without this window.' $ColDim 12
    $foot.Margin = '0,22,0,0'
    $foot.TextWrapping = 'Wrap'
    [void]$panel.Children.Add($foot)
}

function Invoke-FeatureApply {
    $changed = @()
    foreach ($k in @($script:featPending.Keys)) {
        if ([bool]$script:featPending[$k] -ne [bool]$script:featOrig[$k]) { $changed += $k }
    }
    if ($changed.Count -eq 0) { return }

    # Only the switches that undo something need a script run, and only those
    # need RetroBat closed. The rest are a line in a file the next run reads.
    $needsRun = @($changed | Where-Object { [bool]$script:featCat[$_].reverts })

    if ($needsRun.Count -gt 0 -and (Test-RetroBatRunning)) {
        $pick = Show-Choice $WizardName "RetroBat is open.`n`nThis change rewrites files EmulationStation reloads when it closes, so it would be thrown away." @('Close RetroBat for me', 'Cancel')
        if ($pick -ne 'Close RetroBat for me') { return }
        Close-RetroBat
        if (Test-RetroBatRunning) {
            [void](Show-Choice $WizardName 'RetroBat is still open. Close it yourself, then press Apply changes again.' @('OK'))
            return
        }
    }

    $script:featureBarText.Text = 'Working...'
    $script:win.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Render)

    $vals = @{}
    foreach ($k in @($script:featPending.Keys)) { $vals[$k] = [bool]$script:featPending[$k] }

    try { [void](Set-Features -Root $Root -Values $vals) }
    catch {
        Log "features tab: could not write features.ini : $_"
        [void](Show-Choice $WizardName "features.ini could not be written.`n`nDetails are in wizard.log." @('OK'))
        Update-FeatureDirty
        return
    }

    # Log the whole resulting state, not just what changed. Six months from
    # now the useful question is "what was this drive set to".
    $stateText = ((@($script:featCat.Keys) | ForEach-Object {
        "$_=" + $(if ([bool]$vals[$_]) { 'on' } else { 'off' })
    }) -join ' ')
    Log ("features tab applied: " + $stateText)

    # In the update button's own order, and the order is not arbitrary:
    # step 1 puts protected files back, step 2 repairs the Wii launch
    # command and refuses to touch it if the wrapper script step 1 restores
    # is not there yet, step 3 applies settings.
    $ran = 0
    foreach ($sc in @('Restore-ProtectedFiles.ps1', 'Fix-Portability.ps1', 'Apply-Settings.ps1')) {
        $wanted = $false
        foreach ($k in $needsRun) {
            if (@($script:featCat[$k].scripts) -contains $sc) { $wanted = $true }
        }
        if ($wanted) {
            [void](Invoke-Step $sc 'applying the feature change')
            $ran++
        }
    }

    Initialize-FeatureTab
    Render-Features
    $script:uiStatus = Invoke-Health
    Render-Status
    $script:featureBar.Visibility = 'Collapsed'

    if ($ran -gt 0) {
        $script:refreshNote.Text = 'Features applied. Details are in wizard.log.'
    }
    else {
        $script:refreshNote.Text = 'Saved. It takes effect the next time that step runs.'
    }
}


# ===========================================================================
#  The Advanced per-setting editor  (Phase 4 pass 2)
# ---------------------------------------------------------------------------
#  The choices offered here come from RetroBat's OWN es_features.cfg, so they
#  are always the real accepted values for the emulator that will actually
#  run, rather than a list typed out here that would go stale on an update.
#
#  SCOPING IS NOT OPTIONAL. "internal_resolution" is defined EIGHT separate
#  times in that file for different emulators, and they do not agree: under
#  flycast it means "640x480", under dolphin it means "2". Taking the first
#  match would happily write "640x480" into a Dolphin setting and quietly
#  break GameCube and Wii. Every lookup is therefore scoped to the emulator
#  (and where it matters the core) that this console really uses.
# ===========================================================================

# Both the emulator and core name attributes can be comma separated lists,
# e.g. name="libretro, angle" and name="mupen64plus_next, ..._gles3".
function Test-NameInList([string]$Wanted, [string]$List) {
    foreach ($n in ([string]$List -split ',')) { if ($n.Trim() -ieq $Wanted) { return $true } }
    return $false
}

function Get-FeaturesXml {
    if ($script:featuresTried) { return $script:featuresXml }
    $script:featuresTried = $true
    $script:featuresXml   = $null
    $fp = Join-Path $Root 'emulationstation\.emulationstation\es_features.cfg'
    if (Test-Path -LiteralPath $fp) {
        try {
            $doc = New-Object System.Xml.XmlDocument
            $doc.Load($fp)
            $script:featuresXml = $doc
            Log 'read es_features.cfg for the advanced editor'
        }
        catch { Log "could not read es_features.cfg: $_" }
    }
    else { Log 'es_features.cfg not found - the advanced editor falls back to text boxes' }
    return $script:featuresXml
}

# Which emulator (and core) a console actually runs on. es_settings.cfg wins
# when it names one, because that is what RetroBat will really launch.
function Get-ConsoleEmulator([string]$Console) {
    $defaults = @{
        'gamecube' = @('dolphin',  '')
        'wii'      = @('dolphin',  '')
        'wiiu'     = @('cemu',     '')
        '3ds'      = @('azahar',   '')
        'nds'      = @('melonds',  '')
        'n64'      = @('libretro', 'mupen64plus_next')
    }
    $emu = ''; $core = ''
    if ($defaults.ContainsKey($Console)) { $emu = $defaults[$Console][0]; $core = $defaults[$Console][1] }
    if ($null -eq $script:esSettingsText) {
        $script:esSettingsText = ''
        $sp = Join-Path $Root 'emulationstation\.emulationstation\es_settings.cfg'
        if (Test-Path -LiteralPath $sp) {
            try { $script:esSettingsText = [System.IO.File]::ReadAllText($sp) } catch { }
        }
    }
    $m1 = [regex]::Match($script:esSettingsText, ('name="' + [regex]::Escape($Console) + '\.emulator"\s+value="([^"]*)"'))
    if ($m1.Success -and $m1.Groups[1].Value -ne '') { $emu = $m1.Groups[1].Value }
    $m2 = [regex]::Match($script:esSettingsText, ('name="' + [regex]::Escape($Console) + '\.core"\s+value="([^"]*)"'))
    if ($m2.Success -and $m2.Groups[1].Value -ne '') { $core = $m2.Groups[1].Value }
    return @($emu, $core)
}

# Returns a list of @(label, value) pairs, or $null if RetroBat does not
# describe this setting at all (the caller then offers a plain text box).
function Get-FeatureChoices([string]$Console, [string]$Key) {
    $cacheKey = "$Console|$Key"
    if ($script:choiceCache.ContainsKey($cacheKey)) { return $script:choiceCache[$cacheKey] }

    $result     = $null
    $switchLike = $false
    $doc = Get-FeaturesXml
    if ($null -ne $doc) {
        $pair = Get-ConsoleEmulator $Console
        $emu  = [string]$pair[0]
        $core = [string]$pair[1]
        foreach ($f in @($doc.SelectNodes("//feature[@value='$Key']"))) {
            $scopeEmu = ''; $scopeCore = ''
            $n = $f.ParentNode
            while ($null -ne $n) {
                # Two traps in these three lines, both silent, both cost time:
                #
                # 1. $n.Name does NOT give the tag name here. PowerShell's XML
                #    adapter shadows a node's real properties with its
                #    attributes, and these elements have a "name" attribute, so
                #    $n.Name on <emulator name="dolphin"> returns "dolphin".
                #    It looks like it worked and every comparison quietly
                #    fails. $n.get_Name() calls the real property.
                # 2. $n.name for the attribute has the same problem in reverse,
                #    so the attribute is read with GetAttribute.
                if ($n.NodeType -eq 'Element') {
                    $tag = $n.get_Name()
                    if ($tag -eq 'emulator' -and $scopeEmu  -eq '') { $scopeEmu  = $n.GetAttribute('name') }
                    if ($tag -eq 'core'     -and $scopeCore -eq '') { $scopeCore = $n.GetAttribute('name') }
                }
                $n = $n.ParentNode
            }
            if ($emu  -ne '' -and -not (Test-NameInList $emu  $scopeEmu))  { continue }
            if ($core -ne '' -and -not (Test-NameInList $core $scopeCore)) { continue }

            $ch = New-Object System.Collections.ArrayList
            foreach ($c in @($f.SelectNodes('choice'))) {
                [void]$ch.Add(@($c.GetAttribute('name'), $c.GetAttribute('value')))
            }
            if ($ch.Count -gt 0) { $result = $ch; break }
            if ($f.GetAttribute('preset') -like 'switch*') { $switchLike = $true }
        }
    }
    # A "switch" feature has no choice list because it is simply on or off.
    if ($null -eq $result -and $switchLike) {
        $result = New-Object System.Collections.ArrayList
        [void]$result.Add(@('off', '0'))
        [void]$result.Add(@('on',  '1'))
    }
    $script:choiceCache[$cacheKey] = $result
    return $result
}

function Build-AdvancedEditor {
    if ($script:advancedBuilt) { return }
    $script:advancedBuilt = $true
    $wasLoading = $script:profileLoading
    $script:profileLoading = $true

    $panel = $script:advancedPanel
    $panel.Children.Clear()
    $script:choiceValues = @{}
    $mp = $script:mp
    if ($null -eq $mp -or -not $mp.Ok) {
        [void]$panel.Children.Add((New-Text 'No machine to edit.' $ColDim 13))
        $script:profileLoading = $wasLoading
        return
    }

    # --- Breath of the Wild --------------------------------------------------
    #  This one cannot be a tier, a pin or a per-game setting, because the
    #  settings are not RetroBat's at all: they live inside Cemu's own
    #  settings.xml under the game's graphic packs. So it stays a button,
    #  running the same script as Maintenance Steps\Apply Cemu Graphic Packs.bat.
    #
    #  It sat on the front of this tab until 2026-09-18. It is one game on one
    #  emulator, so it belongs in here with the other one-game things.
    #  The section only appears when this drive actually has Cemu on it.
    if (Test-Path -LiteralPath (Join-Path $Root 'emulators\cemu\portable')) {
        $bh = New-Text 'Breath of the Wild, on a slower computer' $ColText 15 $true
        $bh.Margin = '0,0,0,4'
        [void]$panel.Children.Add($bh)
        [void]$panel.Children.Add((New-Text 'Switches on the graphic packs that are already on the drive for it: 720p, lighter shadows, and the two Nvidia smoke and cloud fixes. It only ever adds packs, it backs up Cemu''s settings first, and it is safe to press twice. Close RetroBat first.' $ColDim 13))
        $bwhy = New-Text 'This is NOT the same thing as "One game at a time" further down, and it cannot be folded into it. Everything down there is a RetroBat setting. These are Cemu''s own graphic packs, which RetroBat has no setting for at all - including the resolution, which is the one that actually matters on a Wii U game. So this button has to stay.' $ColDim 12
        $bwhy.Margin = '0,6,0,0'; $bwhy.TextWrapping = 'Wrap'; $bwhy.MaxWidth = 560
        [void]$panel.Children.Add($bwhy)
        $gpBtn = New-Object System.Windows.Controls.Button
        $gpBtn.Content = 'Set up Breath of the Wild'
        $gpBtn.Padding = '14,6'; $gpBtn.FontSize = 14
        $gpBtn.Margin = '0,9,0,18'; $gpBtn.HorizontalAlignment = 'Left'
        $gpBtn.Add_Click({
            if (Test-RetroBatRunning) {
                [void](Show-Choice $WizardName 'RetroBat is open. Close it completely first - Cemu rewrites this file when it closes, so anything changed now would be thrown away.' @('OK'))
                return
            }
            $code = Invoke-Step 'Apply-GraphicPacks.ps1' 'Cemu graphic packs' @{ Quiet = $true }
            if ($code -eq 0) {
                [void](Show-Choice $WizardName ("Done.`n`nIf the game still struggles, drop this computer to LOW at the top of this tab. Exactly what changed is in wizard.log, and Cemu's old settings file is in _ClaudeWorkspace\archive.") @('OK'))
            }
            else {
                [void](Show-Choice $WizardName ("That did not finish, and nothing was left half-done.`n`nThe usual reason is that Cemu or RetroBat is still open. The details are in wizard.log.") @('OK'))
            }
        })
        [void]$panel.Children.Add($gpBtn)
    }

    $ph = New-Text 'Pin an individual setting' $ColText 15 $true
    $ph.Margin = '0,0,0,4'
    [void]$panel.Children.Add($ph)
    [void]$panel.Children.Add((New-Text 'Every setting the Machine tab manages, with the choices RetroBat itself offers. Leave a row on "leave it to the tier" unless you have a reason: a pinned setting stops improving when the tiers improve, forever, on this computer only.' $ColDim 13))

    $labels = @{ 'tier' = 'tier'; 'console-tier' = 'console'; 'vendor' = 'brand'; 'override' = 'PINNED' }

    foreach ($console in @($script:consoles)) {
        $keys = @()
        foreach ($full in @($mp.Settings.Keys)) {
            if ($full -like "$console.*") { $keys += [string]$full }
        }
        if ($keys.Count -eq 0) { continue }

        $h = New-Text $console $ColText 14 $true
        $h.Margin = '0,16,0,4'
        [void]$panel.Children.Add($h)

        foreach ($full in $keys) {
            $short = $full.Substring($console.Length + 1)
            $row = New-Object System.Windows.Controls.StackPanel
            $row.Orientation = 'Horizontal'; $row.Margin = '0,3,0,0'

            $l = New-Text $short $ColText 12
            $l.Width = 250; $l.Margin = '0,6,0,0'
            [void]$row.Children.Add($l)

            $choices = Get-FeatureChoices $console $short
            $pinned  = $script:pendingOverrides.ContainsKey($full)

            if ($null -eq $choices) {
                # RetroBat does not describe this one. Rather than guess at
                # valid values, hand over a plain box: empty means no pin.
                $tb = New-Object System.Windows.Controls.TextBox
                $tb.Width = 230; $tb.FontSize = 12; $tb.Tag = $full
                if ($pinned) { $tb.Text = [string]$script:pendingOverrides[$full] }
                $tb.Add_TextChanged({
                    param($s2, $e2)
                    if ($script:profileLoading) { return }
                    $k = [string]$s2.Tag
                    $v = ([string]$s2.Text).Trim()
                    if ($v -eq '') { if ($script:pendingOverrides.ContainsKey($k)) { $script:pendingOverrides.Remove($k) } }
                    else { $script:pendingOverrides[$k] = $v }
                    Update-ProfileDirty
                })
                [void]$row.Children.Add($tb)
            }
            else {
                $cb = New-Object System.Windows.Controls.ComboBox
                $cb.Width = 230; $cb.FontSize = 12; $cb.Tag = $full
                [void]$cb.Items.Add('leave it to the tier')
                $vals = New-Object System.Collections.ArrayList
                $sel = 0
                $i = 1
                foreach ($pairC in $choices) {
                    [void]$cb.Items.Add(("{0}  [{1}]" -f $pairC[0], $pairC[1]))
                    [void]$vals.Add([string]$pairC[1])
                    if ($pinned -and ([string]$script:pendingOverrides[$full] -eq [string]$pairC[1])) { $sel = $i }
                    $i++
                }
                # a pin RetroBat does not list (hand edited, or a value from an
                # older version) must still be visible rather than silently lost
                if ($pinned -and $sel -eq 0) {
                    [void]$cb.Items.Add(("{0}  [{1}]  (not one of RetroBat's listed choices)" -f 'kept as it is', $script:pendingOverrides[$full]))
                    [void]$vals.Add([string]$script:pendingOverrides[$full])
                    $sel = $vals.Count
                }
                $script:choiceValues[$full] = $vals
                $cb.SelectedIndex = $sel
                $cb.Add_SelectionChanged({
                    param($s2, $e2)
                    if ($script:profileLoading) { return }
                    $k = [string]$s2.Tag
                    if ($s2.SelectedIndex -le 0) {
                        if ($script:pendingOverrides.ContainsKey($k)) { $script:pendingOverrides.Remove($k) }
                    }
                    else {
                        $script:pendingOverrides[$k] = [string]($script:choiceValues[$k])[$s2.SelectedIndex - 1]
                    }
                    Update-ProfileDirty
                })
                [void]$row.Children.Add($cb)
            }

            $src = $labels[[string]$mp.Origin[$full]]
            if (-not $src) { $src = '?' }
            $note = New-Text ("now {0}  ({1})" -f $mp.Settings[$full], $src) $ColDim 12
            $note.Margin = '12,6,0,0'
            [void]$row.Children.Add($note)

            [void]$panel.Children.Add($row)
        }
    }

    # The per-game editor lives at the bottom of the same Advanced section,
    # for the same reason the pins do: it is powerful, it is rarely wanted,
    # and somebody who has not opened Advanced should not have to read past
    # it. It is built at the same time as the pins, which is only when the
    # section is actually opened - both read the 1.4 MB es_features.cfg.
    Build-GameSettingsSection $panel

    $script:profileLoading = $wasLoading
}

# ===========================================================================
#  SETTINGS FOR ONE GAME                              (added 2026-09-18)
# ===========================================================================
#  The tiers, the per-console tiers and the pins all answer "how hard should
#  this computer work at <console>". Sometimes the honest answer is "fine
#  everywhere except this one game", and Breath of the Wild is not the only
#  one - it was just the first to be noticed.
#
#  So: pick a console, pick a game out of the list RetroBat already has, and
#  set anything RetroBat can set for that console for that one game. It is
#  stored in the PROFILE, so the tower and the laptop can disagree about the
#  same game, and it stops applying when another profile is chosen.
#
#  ONLY FOUR CONSOLES ARE OFFERED: Wii, Wii U, DS and 3DS. Those are the
#  heavy ones where a single game can be the problem. Adding another is one
#  entry in $script:GameSettingConsoles, and nothing else.
#
#  THE GAME LIST IS RETROBAT'S OWN, read out of roms\<console>\gamelist.xml.
#  What is stored is the FILE name, not the pretty name, because that is what
#  EmulationStation matches on - the same thing that made Twilight Princess
#  HD scrape as Wind Waker when both were called Zelda.rpx.
# ---------------------------------------------------------------------------
$script:GameSettingConsoles = @('wii', 'wiiu', 'nds', '3ds')
$script:gameListCache = @{}
$script:gsConsole = ''
$script:gsGame    = ''
$script:gsGamePath = ''
$script:gsGameName = ''
$script:gsCtlKinds = @()
$script:gsCtlPreview = $null
$script:gsRowPanel = $null

# The games on one console, newest gamelist.xml wins. Returns an array of
# psobjects with Name and File. Read once per console per window.
function Get-ConsoleGames([string]$Console) {
    if ($script:gameListCache.ContainsKey($Console)) { return $script:gameListCache[$Console] }

    $games = @()
    try {
        $gl = Join-Path $Root ("roms\" + $Console + "\gamelist.xml")
        if (Test-Path -LiteralPath $gl) {
            [xml]$doc = Get-Content -LiteralPath $gl -Raw
            foreach ($g in @($doc.SelectNodes('/gameList/game'))) {
                $path = [string]$g.path
                if ($path -eq '') { continue }
                $file = Split-Path $path -Leaf
                $name = [string]$g.name
                if ($name -eq '') { $name = $file }
                $rel = $path.Trim()
                if ($rel.StartsWith('./')) { $rel = $rel.Substring(2) }
                $games += (New-Object psobject -Property @{ Name = $name; File = $file; Path = $rel })
            }
        }
    }
    catch { Log ("per-game: could not read the {0} game list - {1}" -f $Console, $_.Exception.Message) }

    $games = @($games | Sort-Object Name)
    $script:gameListCache[$Console] = $games
    return $games
}

# console + file name + setting -> the key a profile stores.
function Get-GameSettingKey([string]$Console, [string]$File, [string]$Setting) {
    return ("{0}[{1}].{2}" -f $Console, $File, $Setting)
}

# Everything one tier says about one console, straight out of its own file.
# Read fresh rather than remembered, so improving a tier later improves what
# this offers - the same promise the tiers make everywhere else.
function Get-TierConsoleSettings([string]$Tier, [string]$Console) {
    $out = [ordered]@{}
    try {
        $ini = Read-ProfileIni (Join-Path $Ws ('machine\tiers\' + $Tier + '.ini'))
        if ($ini.Contains($Console)) {
            foreach ($k in ($ini[$Console]).Keys) { $out[$k] = [string](($ini[$Console])[$k]) }
        }
    }
    catch { Log ("per-game: could not read the {0} tier - {1}" -f $Tier, $_.Exception.Message) }
    return $out
}

# Which tier this game is currently set to, or '' for "not set to one".
# A game whose settings match a tier exactly IS that tier; anything else is
# a hand-made mixture and says so rather than pretending to be a tier.
function Get-GameTier([string]$Console, [string]$File) {
    $mine = @{}
    $prefix = ("{0}[{1}]." -f $Console, $File)
    foreach ($k in @($script:pendingGameSettings.Keys)) {
        if ($k.StartsWith($prefix)) { $mine[$k.Substring($prefix.Length)] = [string]$script:pendingGameSettings[$k] }
    }
    if ($mine.Count -eq 0) { return '' }
    foreach ($t in $script:TierNames) {
        $tier = Get-TierConsoleSettings $t $Console
        if ($tier.Count -ne $mine.Count) { continue }
        $same = $true
        foreach ($k in $tier.Keys) {
            if (-not $mine.ContainsKey($k) -or [string]$mine[$k] -ne [string]$tier[$k]) { $same = $false; break }
        }
        if ($same) { return $t }
    }
    return 'custom'
}

# Put one game on a whole tier, or take it off one. Everything this game had
# is cleared first, so switching tiers cannot leave a stray setting from the
# last one behind.
function Set-GameTier([string]$Console, [string]$File, [string]$Tier) {
    $prefix = ("{0}[{1}]." -f $Console, $File)
    foreach ($k in @($script:pendingGameSettings.Keys)) {
        if ($k.StartsWith($prefix)) { $script:pendingGameSettings.Remove($k) }
    }
    if ($Tier -ne '') {
        foreach ($kv in (Get-TierConsoleSettings $Tier $Console).GetEnumerator()) {
            $script:pendingGameSettings[($prefix + $kv.Key)] = [string]$kv.Value
        }
    }
    Update-ProfileDirty
    Build-GameSettingRows
}

function Build-GameSettingsSection($panel) {
    # The two dropdowns start empty every time this is built, so the boxes on
    # screen and these two variables cannot disagree.
    $script:gsConsole = ''
    $script:gsGame    = ''
    $script:gsGamePath = ''
    $script:gsGameName = ''

    $h = New-Text 'One game at a time' $ColText 15 $true
    $h.Margin = '0,26,0,4'
    [void]$panel.Children.Add($h)
    [void]$panel.Children.Add((New-Text 'For when a console is fine except for one game. Pick it here and set whatever RetroBat can set, for that game only. Saved in this machine, so another computer can make its own choice - and Apply changes is what makes it real.' $ColDim 13))

    $pick = New-Object System.Windows.Controls.StackPanel
    $pick.Orientation = 'Horizontal'; $pick.Margin = '0,10,0,0'

    [void]$pick.Children.Add((New-Text 'Console' $ColDim 13))
    $cc = New-Object System.Windows.Controls.ComboBox
    $cc.Width = 110; $cc.FontSize = 13; $cc.Margin = '8,0,0,0'
    [void]$cc.Items.Add('pick one')
    foreach ($c in $script:GameSettingConsoles) {
        if (Test-Path -LiteralPath (Join-Path $Root ("roms\" + $c))) { [void]$cc.Items.Add($c) }
    }
    $cc.SelectedIndex = 0
    $cc.Add_SelectionChanged({
        param($s2, $e2)
        if ($script:profileLoading) { return }
        $v = [string]$s2.SelectedItem
        if ($v -eq 'pick one') { $v = '' }
        $script:gsConsole = $v
        $script:gsGame    = ''
        $script:gsGamePath = ''
        $script:gsGameName = ''
        Update-GameList
        Build-GameSettingRows
    })
    [void]$pick.Children.Add($cc)
    $script:gsConsoleBox = $cc

    [void]$pick.Children.Add((New-Text 'Game' $ColDim 13))
    $gc = New-Object System.Windows.Controls.ComboBox
    $gc.Width = 330; $gc.FontSize = 13; $gc.Margin = '8,0,0,0'
    $gc.Add_SelectionChanged({
        param($s2, $e2)
        if ($script:profileLoading) { return }
        $i = $s2.SelectedIndex
        $games = @(Get-ConsoleGames $script:gsConsole)
        if ($i -ge 1 -and $i -le $games.Count) {
            $script:gsGame     = [string]$games[$i - 1].File
            $script:gsGamePath = [string]$games[$i - 1].Path
            $script:gsGameName = [string]$games[$i - 1].Name
        }
        else { $script:gsGame = ''; $script:gsGamePath = ''; $script:gsGameName = '' }
        Build-GameSettingRows
    })
    [void]$pick.Children.Add($gc)
    $script:gsGameBox = $gc
    [void]$panel.Children.Add($pick)

    $rows = New-Object System.Windows.Controls.StackPanel
    $rows.Margin = '0,10,0,0'
    $script:gsRowPanel = $rows
    [void]$panel.Children.Add($rows)

    # Anything already set on this profile, so a page that has never been
    # touched still SHOWS what is in force. Without this the only way to find
    # out would be to open the .ini.
    $already = @($script:pendingGameSettings.Keys)
    if ($already.Count -gt 0) {
        $t = New-Text 'Already set on this machine:' $ColText 13 $true
        $t.Margin = '0,16,0,4'
        [void]$panel.Children.Add($t)
        foreach ($k in ($already | Sort-Object)) {
            $line = New-Text ("{0}  =  {1}" -f $k, $script:pendingGameSettings[$k]) $ColDim 12
            $line.TextWrapping = 'Wrap'; $line.Margin = '0,2,0,0'
            [void]$panel.Children.Add($line)
        }
    }

    Update-GameList
    Build-GameSettingRows
}

function Update-GameList {
    if ($null -eq $script:gsGameBox) { return }
    $wasLoading = $script:profileLoading
    $script:profileLoading = $true
    $script:gsGameBox.Items.Clear()
    [void]$script:gsGameBox.Items.Add('pick a game')
    if ($script:gsConsole -ne '') {
        foreach ($g in @(Get-ConsoleGames $script:gsConsole)) { [void]$script:gsGameBox.Items.Add([string]$g.Name) }
    }
    $script:gsGameBox.SelectedIndex = 0
    $script:profileLoading = $wasLoading
}

# --- which controllers this game says, and is set to --------------------
#  Wii and Wii U only. Unlike everything else on this tab, the answer lives
#  in _ClaudeWorkspace\controllers.ini and is shared by EVERY computer -
#  which controller a game wants is about the room, not the machine. Only
#  written when Apply changes is pressed, like the rest of the tab.
function Add-ControllerRow {
    if (-not $script:gameInfoOk) { return }
    if (@('wii', 'wiiu') -notcontains $script:gsConsole) { return }
    $kinds = @()
    try { $kinds = @(Get-ControllerKinds $Root $script:gsConsole) } catch { Log "per-game: controller kinds - $_" }
    if ($kinds.Count -eq 0) { return }

    $gKey = ConvertTo-GiKey $script:gsGamePath
    $slot = $script:gsConsole + '|' + $gKey
    $cur = ''
    if ($script:pendingControllers.ContainsKey($slot)) { $cur = [string]$script:pendingControllers[$slot].Kind }
    elseif ($script:origControllers.ContainsKey($slot)) { $cur = [string]$script:origControllers[$slot] }

    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.Margin = '0,0,0,4'
    $l = New-Text 'Controllers (every computer)' $ColText 13 $true
    $l.Width = 250; $l.Margin = '0,6,0,0'
    [void]$row.Children.Add($l)

    $cb = New-Object System.Windows.Controls.ComboBox
    $cb.Width = 430; $cb.FontSize = 13
    $script:gsCtlKinds = $kinds
    $sel = -1; $i = 0
    foreach ($k in $kinds) {
        $m = [string]$k.Menu
        if ($m -eq '') { $m = [string]$k.Name }
        [void]$cb.Items.Add($m)
        if ($k.Name -eq $cur) { $sel = $i }
        $i++
    }
    if ($sel -lt 0) {
        $txt = 'not set yet - the menu shows nothing'
        if ($cur -ne '') { $txt = ("'{0}' - not one of controllers.ini's kinds" -f $cur) }
        [void]$cb.Items.Add($txt)
        $sel = $kinds.Count
    }
    $cb.SelectedIndex = $sel
    $cb.Add_SelectionChanged({
        param($s2, $e2)
        if ($script:profileLoading) { return }
        $i2 = $s2.SelectedIndex
        if ($i2 -lt 0 -or $i2 -ge @($script:gsCtlKinds).Count) { return }
        $k2 = $script:gsCtlKinds[$i2]
        $slot2 = $script:gsConsole + '|' + (ConvertTo-GiKey $script:gsGamePath)
        $script:pendingControllers[$slot2] = New-Object psobject -Property @{
            Console = $script:gsConsole; Path = $script:gsGamePath; Name = $script:gsGameName; Kind = [string]$k2.Name
        }
        if ($null -ne $script:gsCtlPreview) { $script:gsCtlPreview.Text = ('The menu will say:  Controllers: ' + [string]$k2.Label) }
        Update-ProfileDirty
    })
    [void]$row.Children.Add($cb)
    [void]$script:gsRowPanel.Children.Add($row)

    $pv = ''
    if ($sel -lt $kinds.Count) { $pv = 'The menu says:  Controllers: ' + [string]$kinds[$sel].Label }
    $prev = New-Text $pv $ColDim 12
    $prev.TextWrapping = 'Wrap'; $prev.MaxWidth = 680; $prev.Margin = '0,0,0,4'
    $script:gsCtlPreview = $prev
    [void]$script:gsRowPanel.Children.Add($prev)

    if ($script:gsConsole -eq 'wiiu') {
        $n = New-Text 'Real Wii Remotes are all or nothing on Wii U: with them, controllers AND the Wii U GamePad stop working in that game. A game that needs the GamePad cannot go on real Wii Remotes.' $ColDim 12
        $n.TextWrapping = 'Wrap'; $n.MaxWidth = 680; $n.Margin = '0,0,0,12'
        [void]$script:gsRowPanel.Children.Add($n)
    }
    else {
        $n = New-Text 'On Wii this only changes the words in the menu. How the game runs is not affected.' $ColDim 12
        $n.Margin = '0,0,0,12'
        [void]$script:gsRowPanel.Children.Add($n)
    }
}

# One row per setting the chosen console offers, showing what this game is
# currently set to. Rebuilt whenever the console or the game changes.
function Build-GameSettingRows {
    if ($null -eq $script:gsRowPanel) { return }
    $wasLoading = $script:profileLoading
    $script:profileLoading = $true
    $script:gsRowPanel.Children.Clear()

    if ($script:gsConsole -eq '' -or $script:gsGame -eq '') {
        [void]$script:gsRowPanel.Children.Add((New-Text 'Pick a console and a game to see what can be set for it.' $ColDim 12))
        $script:profileLoading = $wasLoading
        return
    }

    Add-ControllerRow

    $mp = $script:mp
    $keys = @()
    if ($null -ne $mp -and $mp.Ok) {
        foreach ($full in @($mp.Settings.Keys)) {
            if ($full -like ($script:gsConsole + '.*')) { $keys += [string]$full }
        }
    }
    if ($keys.Count -eq 0) {
        [void]$script:gsRowPanel.Children.Add((New-Text 'The machine settings have nothing listed for this console.' $ColDim 12))
        $script:profileLoading = $wasLoading
        return
    }

    $f = New-Text ("File name: " + $script:gsGame) $ColDim 12
    $f.Margin = '0,0,0,10'; $f.TextWrapping = 'Wrap'
    [void]$script:gsRowPanel.Children.Add($f)

    # --- the easy answer, first --------------------------------------------
    #  Almost nobody wants to know what melonds_polygon does. What they want
    #  is "this one game stutters and the rest of the console is fine", and
    #  the honest answer to that is "run this game at the Low tier" - which is
    #  the same sentence the per-console tiers already say, one level further
    #  in. It reads the tier's file at the moment you pick it, so a game set
    #  to Low keeps improving whenever the Low tier improves.
    $tierRow = New-Object System.Windows.Controls.StackPanel
    $tierRow.Orientation = 'Horizontal'; $tierRow.Margin = '0,0,0,6'
    $tl = New-Text 'Run this game at' $ColText 13 $true
    $tl.Width = 250; $tl.Margin = '0,6,0,0'
    [void]$tierRow.Children.Add($tl)

    $tcb = New-Object System.Windows.Controls.ComboBox
    $tcb.Width = 230; $tcb.FontSize = 13
    [void]$tcb.Items.Add('same as the rest of the console')
    [void]$tcb.Items.Add('low  -  smoothest')
    [void]$tcb.Items.Add('medium')
    [void]$tcb.Items.Add('high  -  best picture')
    $cur = Get-GameTier $script:gsConsole $script:gsGame
    switch ($cur) {
        'low'    { $tcb.SelectedIndex = 1 }
        'medium' { $tcb.SelectedIndex = 2 }
        'high'   { $tcb.SelectedIndex = 3 }
        'custom' { [void]$tcb.Items.Add('settings of your own, below'); $tcb.SelectedIndex = 4 }
        default  { $tcb.SelectedIndex = 0 }
    }
    $tcb.Add_SelectionChanged({
        param($s2, $e2)
        if ($script:profileLoading) { return }
        $i = $s2.SelectedIndex
        $t = ''
        if ($i -eq 1) { $t = 'low' } elseif ($i -eq 2) { $t = 'medium' } elseif ($i -eq 3) { $t = 'high' }
        elseif ($i -ge 4) { return }   # "settings of your own" is a description, not a choice
        Set-GameTier $script:gsConsole $script:gsGame $t
    })
    [void]$tierRow.Children.Add($tcb)
    [void]$script:gsRowPanel.Children.Add($tierRow)

    [void]$script:gsRowPanel.Children.Add((New-Text 'That is the whole answer for "this one game stutters". It fills in every setting below from that tier, for this game only. Press Apply changes to make it real.' $ColDim 12))

    # Wii U is the honest exception and it is worth saying so here rather
    # than letting somebody set Mario Kart to Low and wonder why nothing
    # happened. Cemu's resolution lives in its graphic packs, which RetroBat
    # has no setting for at all - hence the separate button further up.
    if ($script:gsConsole -eq 'wiiu') {
        $warn = New-Text 'Wii U is the exception: the setting that actually matters for a Wii U game is Cemu''s resolution, and RetroBat has no control over it - it lives in Cemu''s graphic packs. For a heavy Wii U game use the "Set up Breath of the Wild" button above instead. This tier still changes the few things RetroBat can reach.' '#FFE5B83B' 12
        $warn.Margin = '0,6,0,0'; $warn.TextWrapping = 'Wrap'; $warn.MaxWidth = 560
        [void]$script:gsRowPanel.Children.Add($warn)
    }

    $sep = New-Text 'Or set them one at a time:' $ColText 13 $true
    $sep.Margin = '0,14,0,4'
    [void]$script:gsRowPanel.Children.Add($sep)

    foreach ($full in $keys) {
        $short  = $full.Substring($script:gsConsole.Length + 1)
        $gsKey  = Get-GameSettingKey $script:gsConsole $script:gsGame $short
        $isSet  = $script:pendingGameSettings.ContainsKey($gsKey)

        $row = New-Object System.Windows.Controls.StackPanel
        $row.Orientation = 'Horizontal'; $row.Margin = '0,3,0,0'
        $l = New-Text $short $ColText 12
        $l.Width = 250; $l.Margin = '0,6,0,0'
        [void]$row.Children.Add($l)

        $choices = Get-FeatureChoices $script:gsConsole $short

        if ($null -eq $choices) {
            $tb = New-Object System.Windows.Controls.TextBox
            $tb.Width = 230; $tb.FontSize = 12; $tb.Tag = $gsKey
            if ($isSet) { $tb.Text = [string]$script:pendingGameSettings[$gsKey] }
            $tb.Add_TextChanged({
                param($s2, $e2)
                if ($script:profileLoading) { return }
                $k = [string]$s2.Tag
                $v = ([string]$s2.Text).Trim()
                if ($v -eq '') { if ($script:pendingGameSettings.ContainsKey($k)) { $script:pendingGameSettings.Remove($k) } }
                else { $script:pendingGameSettings[$k] = $v }
                Update-ProfileDirty
            })
            [void]$row.Children.Add($tb)
        }
        else {
            $cb = New-Object System.Windows.Controls.ComboBox
            $cb.Width = 230; $cb.FontSize = 12; $cb.Tag = $gsKey
            [void]$cb.Items.Add('same as the rest of the console')
            $vals = New-Object System.Collections.ArrayList
            $sel = 0; $i = 1
            foreach ($pairC in $choices) {
                [void]$cb.Items.Add(("{0}  [{1}]" -f $pairC[0], $pairC[1]))
                [void]$vals.Add([string]$pairC[1])
                if ($isSet -and ([string]$script:pendingGameSettings[$gsKey] -eq [string]$pairC[1])) { $sel = $i }
                $i++
            }
            # A value RetroBat does not list - hand edited, or from an older
            # version - must stay visible rather than be silently dropped.
            if ($isSet -and $sel -eq 0) {
                [void]$cb.Items.Add(("kept as it is  [{0}]  (not one of RetroBat's listed choices)" -f $script:pendingGameSettings[$gsKey]))
                [void]$vals.Add([string]$script:pendingGameSettings[$gsKey])
                $sel = $vals.Count
            }
            $script:choiceValues[$gsKey] = $vals
            $cb.SelectedIndex = $sel
            $cb.Add_SelectionChanged({
                param($s2, $e2)
                if ($script:profileLoading) { return }
                $k = [string]$s2.Tag
                if ($s2.SelectedIndex -le 0) {
                    if ($script:pendingGameSettings.ContainsKey($k)) { $script:pendingGameSettings.Remove($k) }
                }
                else {
                    $script:pendingGameSettings[$k] = [string]($script:choiceValues[$k])[$s2.SelectedIndex - 1]
                }
                Update-ProfileDirty
            })
            [void]$row.Children.Add($cb)
        }

        $note = New-Text ("console is on {0}" -f $mp.Settings[$full]) $ColDim 12
        $note.Margin = '12,6,0,0'
        [void]$row.Children.Add($note)
        [void]$script:gsRowPanel.Children.Add($row)
    }

    $script:profileLoading = $wasLoading
}


# --- writing the [overrides] section ---------------------------------------

function Remove-TrailingBlanks($out) {
    while ($out.Count -gt 0 -and [string]$out[$out.Count - 1] -eq '') { $out.RemoveAt($out.Count - 1) }
}

function Format-PinLine([string]$Key, [string]$Value, [string]$Comment = '') {
    $pad = 31
    if ($Key.Length -ge $pad) { $pad = $Key.Length + 1 }
    $line = $Key.PadRight($pad) + '= ' + $Value
    if ($Comment -ne '') { $line = $line.PadRight(44) + '  ' + $Comment }
    return $line
}

function Add-NewPins($out, $remaining) {
    Remove-TrailingBlanks $out
    if ($remaining.Count -eq 0) { return }
    $stamp = Get-Date -Format 'yyyy-MM-dd'
    foreach ($k in ($remaining.Keys | Sort-Object)) {
        $out.Add((Format-PinLine $k ([string]$remaining[$k]) "; pinned from the Setup Wizard, $stamp"))
    }
}

# Rewrites [overrides] while keeping the comments, including the trailing
# "why" comment on any line whose value has not changed. Those annotations are
# most of what makes this file worth reading.
# Rewrites ONE section of a profile file, keeping every other line and every
# comment exactly as it was. Used for [overrides] and, since 2026-09-18, for
# [game-settings] as well - the job is identical and two copies of this would
# be two copies to keep in step.
function Set-ProfileOverrides {
    [CmdletBinding()]
    param(
        [string]    $ProfileFile,
        [hashtable] $Pins,
        [string]    $Section = 'overrides',
        [string]    $Header  = '; Individual settings pinned for this machine only.'
    )
    $lines = @([System.IO.File]::ReadAllLines($ProfileFile))
    $remaining = @{}
    foreach ($k in $Pins.Keys) { $remaining[$k] = [string]$Pins[$k] }

    $out = New-Object System.Collections.Generic.List[string]
    $inSection = $false
    $found     = $false
    $dropCont  = $false

    foreach ($line in $lines) {
        $t = ([string]$line).Trim()

        if ($t.StartsWith('[') -and $t.EndsWith(']')) {
            if ($inSection) { Add-NewPins $out $remaining; $out.Add('') }
            $inSection = ($t -ieq ('[' + $Section + ']'))
            if ($inSection) { $found = $true }
            $dropCont = $false
            $out.Add($line)
            continue
        }
        if (-not $inSection) { $out.Add($line); continue }

        if ($t -eq '') { $dropCont = $false; $out.Add($line); continue }

        if ($t.StartsWith(';') -or $t.StartsWith('#')) {
            # A deeply indented comment straight after a line we just removed or
            # rewrote is that line's own trailing comment, wrapped onto a second
            # line. It has to go with it, or it dangles under something else.
            if ($dropCont -and ([string]$line -match '^\s{20,}[;#]')) { continue }
            $dropCont = $false
            $out.Add($line); continue
        }

        $eq = $t.IndexOf('=')
        if ($eq -lt 1) { $dropCont = $false; $out.Add($line); continue }
        $key = $t.Substring(0, $eq).Trim()
        $oldVal = $t.Substring($eq + 1)
        $semi = $oldVal.IndexOf(';')
        if ($semi -ge 0) { $oldVal = $oldVal.Substring(0, $semi) }
        $oldVal = $oldVal.Trim()

        if ($remaining.ContainsKey($key)) {
            $newVal = [string]$remaining[$key]
            $remaining.Remove($key)
            if ($newVal -eq $oldVal) {
                $out.Add($line)          # unchanged: keep the line and its reason
                $dropCont = $false
            }
            else {
                $out.Add((Format-PinLine $key $newVal))   # changed: the old reason may no longer be true
                $dropCont = $true
            }
        }
        else {
            $dropCont = $true            # un-pinned: drop it and its wrapped comment
        }
    }

    if ($inSection) { Add-NewPins $out $remaining }
    elseif (-not $found) {
        $out.Add('')
        $out.Add('[' + $Section + ']')
        $out.Add($Header)
        Add-NewPins $out $remaining
    }

    [System.IO.File]::WriteAllLines($ProfileFile, $out, (New-Object System.Text.UTF8Encoding($false)))
}

# ===========================================================================
#  THE SAVES TAB   (Phase 5, added 2026-08-29)
# ===========================================================================
#  A window over what SaveBackups\ already does, and nothing more. Every rule
#  about what counts as a game lives in scripts\SaveIndex.ps1, which is shared
#  with SaveBackups\Browse My Saves.bat, so the button and the window can
#  never disagree with each other.
#
#  WHY IT DOES NOT WALK THE VERSIONS FOLDER
#    SaveBackups\Versions\ holds thousands of entries, most of them Wii and
#    3DS internal memory. Listing it takes tens of seconds on a USB drive,
#    which is exactly why the old Restore A Save button feels slow. This tab
#    reads index.json instead, which is one file, and only opens a game's own
#    history folders when that game is clicked.
#
#  THE ONE REAL IMPROVEMENT OVER THE OLD BUTTON
#    Wii and 3DS keep a single game's save in SEVERAL files. The old tool
#    listed them separately and printed a warning telling you to restore each
#    one and match the dates by hand. This groups them and puts the whole set
#    back from one moment in time, choosing for each file the newest version
#    that existed at or before that moment. A file with no version that old
#    did not exist yet and is left alone, and it says so.
# ===========================================================================

$script:saveGames    = @()
$script:saveList     = @()
$script:saveShowAll  = $false
$script:saveSelected = $null
$script:saveConsole  = 'All consoles'
$script:saveConsoleLoading = $false
$script:saveFound    = @{}

# A small dark dialog that asks for one line of text. Show-Choice only offers
# buttons, and naming a game needs typing. Same script-scope rule as
# Show-Choice: event handlers cannot see a function's local variables.
function Show-TextInput([string]$Title, [string]$Message, [string]$Default = '') {
    Close-Splash
    $w = New-Object System.Windows.Window
    $w.Title = $Title; $w.Width = 460; $w.SizeToContent = 'Height'
    $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'NoResize'
    $w.Background = (New-Brush $ColBg); $w.Topmost = $true
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '22'
    $msg = New-Text $Message $ColText 14; $msg.Margin = '0,0,0,12'
    [void]$sp.Children.Add($msg)
    $box = New-Object System.Windows.Controls.TextBox
    $box.Text = $Default; $box.FontSize = 15; $box.Padding = '6,4'
    [void]$sp.Children.Add($box)
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.HorizontalAlignment = 'Right'; $row.Margin = '0,16,0,0'
    $script:textResult = ''
    $script:textWin    = $w
    $script:textBox    = $box
    foreach ($label in @('Cancel', 'Save')) {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $label; $b.Margin = '8,0,0,0'; $b.Padding = '16,7'; $b.FontSize = 14; $b.Tag = $label
        $b.Add_Click({
            param($s, $e)
            if ([string]$s.Tag -eq 'Save') { $script:textResult = [string]$script:textBox.Text }
            $script:textWin.Close()
        })
        [void]$row.Children.Add($b)
    }
    [void]$sp.Children.Add($row)
    $w.Content = $sp
    [void]$w.ShowDialog()
    return $script:textResult
}

# Reads the backup index. No disk walking, so this is cheap enough to re-run
# after every backup and every restore.
function Initialize-Saves {
    $script:saveBackupRoot  = Join-Path $Ws 'SaveBackups'
    $script:saveVersionRoot = Join-Path $script:saveBackupRoot 'Versions'
    $script:saveIndexPath   = Join-Path $script:saveBackupRoot 'index.json'
    $script:saveNamesPath   = Join-Path $script:saveBackupRoot 'game-name-shortcuts.txt'
    $script:saveGames       = @()
    $script:saveSelected    = $null
    try {
        # Work out what the game codes mean, if that has not been done lately.
        # It is cached in game-names-found.txt and only rebuilt when it is
        # missing, a month old, or a gamelist.xml has changed (which happens
        # when games are added or re-scraped). Well under a second either way.
        try {
            if (Update-GameNameCache -Root $Root -BackupRoot $script:saveBackupRoot) {
                Log 'saves tab: rebuilt the found-names list'
            }
        }
        catch { Log ("saves tab: could not work out game names - {0}" -f $_.Exception.Message) }

        $script:saveFound = Read-GameNameCache (Get-GameNameCachePath $script:saveBackupRoot) $Root

        $idx = Read-SaveIndex $script:saveIndexPath
        $nms = Read-GameNames $script:saveNamesPath
        $script:saveGames = @(Get-SaveGames -Index $idx -Names $nms -Found $script:saveFound)

        # The mid-game autosaves Quarantine-Savestates.ps1 has put aside. They
        # are attached to the games they belong to rather than being given a
        # section of their own, because a section at the bottom is a section
        # nobody opens.
        $qRoot  = Join-Path $Ws 'archive\quarantined-savestates'
        $states = @(Get-QuarantinedSavestates $qRoot)
        $script:saveGames = @(Add-SavestatesToGames -Games $script:saveGames -Savestates $states -Found $script:saveFound)

        Log ("saves tab: {0} groups from {1} tracked files, {2} names known, {3} mid-game autosaves" -f `
             $script:saveGames.Count, $idx.Count, $script:saveFound.Count, $states.Count)
    }
    catch { Log ("saves tab: could not read the backup index - {0}" -f $_.Exception.Message) }
}

# Fills the console dropdown from the systems actually present, so it never
# offers a console this drive does not have.
function Render-SaveConsoleList {
    $cb = $script:saveConsoleBx
    $script:saveConsoleLoading = $true      # stop SelectionChanged firing while filling
    $cb.Items.Clear()
    [void]$cb.Items.Add('All consoles')
    $pool = @($script:saveGames | Where-Object { $script:saveShowAll -or $_.Category -eq 'game' })
    foreach ($sys in @($pool | ForEach-Object { $_.System } | Sort-Object -Unique)) {
        [void]$cb.Items.Add($sys)
    }
    if ($cb.Items.Contains($script:saveConsole)) { $cb.SelectedItem = $script:saveConsole }
    else { $cb.SelectedIndex = 0; $script:saveConsole = 'All consoles' }
    $script:saveConsoleLoading = $false
}

function Render-SaveGames {
    $lb = $script:saveListBox
    $lb.Items.Clear()
    $script:saveList = @($script:saveGames | Where-Object {
        ($script:saveShowAll -or $_.Category -eq 'game') -and
        ($script:saveConsole -eq 'All consoles' -or $_.System -eq $script:saveConsole)
    })

    foreach ($g in $script:saveList) {
        $when = ''
        if ($g.Changed -gt [datetime]::MinValue) { $when = $g.Changed.ToString('ddd  yyyy-MM-dd  HH:mm') }
        $tag = ''
        if ($g.Category -eq 'arcade') { $tag = '   (arcade memory)' }
        if ($g.Category -eq 'system') { $tag = '   (system files)' }
        # Marked right here in the main list, on purpose.
        if ($g.Savestates -and $g.Savestates.Count -gt 0) {
            $tag += ('   * {0} MID-GAME AUTOSAVE{1}' -f $g.Savestates.Count,
                     $(if ($g.Savestates.Count -eq 1) { '' } else { 'S' }))
        }
        [void]$lb.Items.Add(('{0}   [{1}]   {2}{3}' -f $g.DisplayName, $g.System, $when, $tag))
    }

    if ($script:saveList.Count -eq 0) {
        $script:saveNote.Text = 'Nothing has been backed up yet. Press "Back up saves now".'
    }
    elseif ($script:saveShowAll) {
        $script:saveNote.Text = ('{0} shown, everything' -f $script:saveList.Count)
    }
    else {
        $hidden = $script:saveGames.Count - $script:saveList.Count
        $script:saveNote.Text = ('{0} game saves, {1} arcade and system entries hidden' -f $script:saveList.Count, $hidden)
    }
    Render-SaveDetail
}

function Render-SaveDetail {
    $p = $script:saveDetail
    $p.Children.Clear()
    $g = $script:saveSelected

    if ($null -eq $g) {
        $t = New-Text 'Pick something on the left to see the versions you can go back to.' $ColDim 14
        $t.Margin = '0,10,0,0'
        [void]$p.Children.Add($t)
        return
    }

    [void]$p.Children.Add((New-SectionHeader $g.DisplayName))

    # The box art, if this game has any. Wrapped in its own try/catch: a
    # missing or damaged picture must never take the whole tab down with it,
    # and BitmapImage throws rather than returning nothing.
    if ($g.Image) {
        try {
            $imgPath = Join-Path $Root $g.Image
            if (Test-Path -LiteralPath $imgPath) {
                $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
                $bmp.BeginInit()
                $bmp.UriSource = New-Object System.Uri($imgPath)
                # OnLoad reads the picture now and lets the file go again.
                # Without it WPF holds the file open, and a drive with an open
                # file on it will not eject.
                $bmp.CacheOption = 'OnLoad'
                $bmp.EndInit()
                $im = New-Object System.Windows.Controls.Image
                $im.Source = $bmp
                $im.MaxHeight = 150
                $im.HorizontalAlignment = 'Left'
                $im.Margin = '0,4,0,10'
                [void]$p.Children.Add($im)
            }
        }
        catch { Log ("saves tab: could not show artwork for {0} - {1}" -f $g.DisplayName, $_.Exception.Message) }
    }

    [void]$p.Children.Add((New-LabelledRow 'System' ([string]$g.System)))
    if ($g.Name -and $g.Name -ne $g.GameId) {
        # "a name you typed" was wrong and confusing: eleven of these lines
        # were written into game-name-shortcuts.txt during the build, not by
        # Steven, so saves he had never touched claimed he had named them.
        # What is actually true is which FILE the name came from.
        $src = if ($g.NameSource -eq 'yours') { 'set by hand, in game-name-shortcuts.txt' } else { 'found on this drive' }
        [void]$p.Children.Add((New-LabelledRow 'Code' ('{0}   ({1})' -f $g.GameId, $src)))
    }
    if ($g.Files.Count -gt 0) {
        [void]$p.Children.Add((New-LabelledRow 'Made of' ('{0} file(s), {1}' -f $g.Files.Count, (Format-SaveSize $g.Bytes))))
    }
    if ($g.Changed -gt [datetime]::MinValue) {
        [void]$p.Children.Add((New-LabelledRow 'Last changed' $g.Changed.ToString('ddd  yyyy-MM-dd  HH:mm')))
    }

    foreach ($f in @($g.Files | Select-Object -First 12)) {
        $t = New-Text ('    ' + (Split-Path $f -Leaf)) $ColDim 12
        [void]$p.Children.Add($t)
    }
    if ($g.Files.Count -gt 12) {
        [void]$p.Children.Add((New-Text ('    ... and {0} more' -f ($g.Files.Count - 12)) $ColDim 12))
    }

    # An id with no friendly name yet. Naming it writes one line into
    # game-name-shortcuts.txt, which is where those names have always lived.
    if ($g.Category -ne 'system' -and -not $g.Name) {
        $nb = New-Object System.Windows.Controls.Button
        $nb.Content = 'Give this a name'; $nb.Padding = '12,5'; $nb.FontSize = 13
        $nb.Margin = '0,10,0,0'; $nb.HorizontalAlignment = 'Left'; $nb.Tag = $g.GameId
        $nb.Add_Click({ param($s, $e) Invoke-SaveNameGame ([string]$s.Tag) })
        [void]$p.Children.Add($nb)
        $hint = New-Text 'Nintendo names saves by code. A name here is kept for good.' $ColDim 12
        $hint.Margin = '0,4,0,0'
        [void]$p.Children.Add($hint)
    }

    if ($g.Category -eq 'arcade') {
        $w = New-Text 'Arcade board memory. Usually just high scores and machine settings.' $ColDim 13
        $w.Margin = '0,12,0,0'
        [void]$p.Children.Add($w)
    }
    if ($g.Category -eq 'system') {
        $w = New-Text 'Files the console keeps for itself, not one game. You almost never want these.' '#FFE5B83B' 13
        $w.Margin = '0,12,0,0'
        [void]$p.Children.Add($w)
    }

    # --- the restore points -------------------------------------------------
    #  The ORDINARY saves come first and the mid-game autosaves go underneath
    #  them, because the ordinary ones are what somebody is nearly always here
    #  for. Do not put the autosaves back on top.
    if ($g.Files.Count -eq 0) {
        $t = New-Text 'No ordinary save data for this game, only the autosaves below.' $ColDim 13
        $t.Margin = '0,14,0,0'
        [void]$p.Children.Add($t)
        Add-SavestateSection $p $g
        return
    }

    [void]$p.Children.Add((New-SectionHeader 'Go back to'))

    $points = @()
    try { $points = @(Get-SaveRestorePoints $script:saveVersionRoot $g.Files) }
    catch { Log ("saves tab: could not read history - {0}" -f $_.Exception.Message) }

    if ($points.Count -eq 0) {
        [void]$p.Children.Add((New-Text 'No backed up versions of this one yet.' $ColDim 13))
        Add-SavestateSection $p $g
        return
    }

    $shown = 0
    foreach ($pt in $points) {
        $shown++
        if ($shown -gt 40) {
            [void]$p.Children.Add((New-Text ('... and {0} older ones. Use SaveBackups\Browse My Saves.bat to see them all.' -f ($points.Count - 40)) $ColDim 12))
            break
        }
        $row = New-Object System.Windows.Controls.StackPanel
        $row.Orientation = 'Horizontal'; $row.Margin = '0,3'

        $b = New-Object System.Windows.Controls.Button
        $b.Content = 'Put back'; $b.Padding = '10,3'; $b.FontSize = 12; $b.Width = 80
        $b.Tag = [string]$pt.Stamp
        $b.Add_Click({ param($s, $e) Invoke-SaveRestore ([string]$s.Tag) })
        [void]$row.Children.Add($b)

        $label = '  {0}     {1} of the files changed here' -f $pt.When, $pt.Changed
        if ($shown -eq 1) { $label += '   (this is what you have now)' }
        $t = New-Text $label $ColText 13
        $t.Margin = '8,4,0,0'
        [void]$row.Children.Add($t)

        [void]$p.Children.Add($row)
    }

    Add-SavestateSection $p $g
}

# ---------------------------------------------------------------------------
#  The mid-game autosaves, drawn UNDERNEATH the ordinary saves
# ---------------------------------------------------------------------------
function Add-SavestateSection($p, $g) {
    if (-not $g.Savestates -or $g.Savestates.Count -eq 0) { return }

    [void]$p.Children.Add((New-SectionHeader 'Mid-game autosaves'))
    $w = New-Text 'Snapshots the emulator took mid-play, not ordinary saves. Held aside so one cannot load by accident.' $ColDim 12
    $w.Margin = '0,0,0,8'
    [void]$p.Children.Add($w)

    $shownS = 0
    foreach ($st in @($g.Savestates)) {
        $shownS++
        if ($shownS -gt 8) {
            [void]$p.Children.Add((New-Text ('... and {0} older ones.' -f ($g.Savestates.Count - 8)) $ColDim 12))
            break
        }
        $row = New-Object System.Windows.Controls.StackPanel
        $row.Orientation = 'Horizontal'; $row.Margin = '0,4'

        $b = New-Object System.Windows.Controls.Button
        $b.Content = 'Put back'; $b.Padding = '10,3'; $b.FontSize = 12; $b.Width = 80
        $b.Margin = '0,10,10,0'
        # The identity, not an index: the list is rebuilt after every action.
        $b.Tag = '{0}|{1}' -f $st.When.ToString('yyyy-MM-dd_HHmmss'), $st.Slot
        $b.Add_Click({ param($s2, $e2) Invoke-SavestateRestore ([string]$s2.Tag) })
        [void]$row.Children.Add($b)

        # The .png beside a savestate is a screenshot of that exact moment.
        if ($st.Thumb) {
            try {
                $bmp2 = New-Object System.Windows.Media.Imaging.BitmapImage
                $bmp2.BeginInit()
                $bmp2.UriSource = New-Object System.Uri($st.Thumb)
                $bmp2.CacheOption = 'OnLoad'      # do not hold the file open
                $bmp2.EndInit()
                $im2 = New-Object System.Windows.Controls.Image
                $im2.Source = $bmp2; $im2.MaxHeight = 46; $im2.Margin = '0,0,10,0'
                [void]$row.Children.Add($im2)
            }
            catch { Log ("saves tab: could not show an autosave screenshot - {0}" -f $_.Exception.Message) }
        }

        $t = New-Text ('{0}   slot {1}   ({2})' -f `
             $st.When.ToString('ddd  yyyy-MM-dd  HH:mm'), $st.Slot, (Format-SaveSize $st.Size)) $ColText 13
        $t.Margin = '0,12,0,0'
        [void]$row.Children.Add($t)
        [void]$p.Children.Add($row)
    }
}

# ---------------------------------------------------------------------------
#  Actions
# ---------------------------------------------------------------------------

function Invoke-SaveNameGame([string]$Code) {
    if (-not $Code) { return }

    # An empty text box is a cruel thing to show somebody who has no idea what
    # HAGE is. What IS known is the console, so the games on that console that
    # no save has been matched to yet are offered as a list first. Typing it
    # yourself is always still there, and the list is skipped entirely if it
    # comes back empty.
    $name   = ''
    $system = ''
    $g = $script:saveSelected
    if ($null -ne $g) { $system = [string]$g.System }

    $choices = @()
    if ($system -and (Get-Command Get-UnmatchedGameNames -ErrorAction SilentlyContinue)) {
        $used = @()
        foreach ($x in @($script:saveGames)) {
            if ([string]$x.System -eq $system -and $x.Name) { $used += [string]$x.Name }
        }
        try { $choices = @(Get-UnmatchedGameNames -Root $Root -System $system -UsedNames $used) }
        catch { Log ("saves tab: could not list unmatched games - {0}" -f $_.Exception.Message) }
    }

    if ($choices.Count -gt 0) {
        $pick = Show-ListPick 'Name this save' ("What game is {0}?`n`nThese are the {1} games on this drive that no save has been matched to yet." -f $Code, $system) $choices
        if ($pick -eq '')  { return }
        if ($pick -ne '?') { $name = $pick }
    }

    if ($name -eq '') {
        $name = Show-TextInput 'Name this save' ("What game is {0}?`n`nThis writes one line into game-name-shortcuts.txt and is used everywhere from now on." -f $Code) ''
    }
    if (-not $name) { return }
    if (Add-GameName $script:saveNamesPath $name $Code) {
        Log ("saves tab: named {0} as '{1}'" -f $Code, $name)
        $keepSystem = $script:saveSelected.System
        Initialize-Saves
        $script:saveSelected = @($script:saveGames | Where-Object { $_.GameId -eq $Code -and $_.System -eq $keepSystem })[0]
        Render-SaveConsoleList
        Render-SaveGames
    }
    else {
        [void](Show-Choice 'Setup Wizard' 'That name could not be saved. See wizard.log.' @('OK'))
    }
}

# Putting a mid-game autosave back. Deliberately noisier than an ordinary
# restore: this one hands a loaded weapon back to the user, so it says what it
# is, what it will do, and that it does not last.
function Invoke-SavestateRestore([string]$Ident) {
    $g = $script:saveSelected
    if ($null -eq $g -or -not $Ident) { return }

    $st = $null
    foreach ($x in @($g.Savestates)) {
        if (('{0}|{1}' -f $x.When.ToString('yyyy-MM-dd_HHmmss'), $x.Slot) -eq $Ident) { $st = $x; break }
    }
    if ($null -eq $st) { return }

    if (Test-RetroBatRunning) {
        [void](Show-Choice 'Setup Wizard' "RetroBat is open. Close it first." @('OK'))
        return
    }

    $msg = "PUT BACK A MID-GAME AUTOSAVE?`n`n" +
           "{0}, slot {1}, from {2}.`n`n" +
           "This is NOT an ordinary save. It drops you back into the middle of that moment, and if you save on top of it afterwards you overwrite whatever you have done since.`n`n" +
           "It also does not last: savestates are moved aside again when the next game exits, so load it before then.`n`n" +
           "The archived copy is kept either way."
    $msg = $msg -f $g.DisplayName, $st.Slot, $st.When.ToString('ddd d MMM yyyy, HH:mm')

    $answer = Show-Choice 'Put back a mid-game autosave' $msg @('Cancel', 'Put it back')
    if ($answer -ne 'Put it back') { Log 'saves tab: autosave restore cancelled'; return }

    $res = $null
    try { $res = Restore-Savestate -Root $Root -Savestate $st -System ([string]$g.System) }
    catch {
        Log ("saves tab: autosave restore threw - {0}" -f $_.Exception.Message)
        [void](Show-Choice 'Setup Wizard' ("That did not work:`n`n{0}" -f $_.Exception.Message) @('OK'))
        return
    }

    Log ("saves tab: autosave restore, {0} put back, {1} skipped" -f $res.Restored, $res.Skipped)
    foreach ($m in @($res.Messages)) { Log ('   ' + $m) }

    if ($res.Restored -eq 0) {
        [void](Show-Choice 'Setup Wizard' "Nothing was put back. See wizard.log." @('OK'))
    }
    else {
        [void](Show-Choice 'Setup Wizard' ("Done. It is back in Dolphin's savestate slot {0}.`n`nLoad it before the next game exits." -f $st.Slot) @('OK'))
    }
}

function Invoke-SaveBackupNow {
    $script:saveNote.Text = 'Backing up...'
    $script:win.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Render)
    $code = Invoke-Step 'Backup-RetroBatSaves.ps1' 'back up saves' @{ Quiet = $true }
    Initialize-Saves
    Render-SaveConsoleList
    Render-SaveGames
    if ($code -ne 0) { $script:saveNote.Text = 'The backup reported a problem - see wizard.log.' }
    else             { $script:saveNote.Text = 'Backed up.' }
}

function Invoke-SaveRestore([string]$Stamp) {
    $g = $script:saveSelected
    if ($null -eq $g -or -not $Stamp) { return }

    # A running game writes its own save on exit, straight over anything put
    # back now. Same reason settings changes refuse while RetroBat is open.
    if (Test-RetroBatRunning) {
        [void](Show-Choice 'Setup Wizard' `
            "RetroBat is open.`n`nClose it first. A game that is running will write its own save over anything put back now." `
            @('OK'))
        return
    }

    $snap = @()
    try { $snap = @(Resolve-SaveSnapshot $script:saveVersionRoot $g.Files $Stamp) }
    catch { Log ("saves tab: could not work out the snapshot - {0}" -f $_.Exception.Message); return }
    if ($snap.Count -eq 0) { return }

    $when = Format-SaveStamp $Stamp

    $lines = @()
    foreach ($s in @($snap | Select-Object -First 10)) {
        if ($s.Missing) { $lines += ('   leave alone   {0}   (did not exist yet)' -f (Split-Path $s.Rel -Leaf)) }
        else            { $lines += ('   put back      {0}   from {1}' -f (Split-Path $s.Rel -Leaf), $s.When) }
    }
    if ($snap.Count -gt 10) { $lines += ('   ... and {0} more' -f ($snap.Count - 10)) }

    $msg = "Put {0} back to how it was on {1}?`n`n{2}`n`nWhat is there now is kept first, so this can be undone by putting the newest version back again." -f `
           $g.DisplayName, $when, ($lines -join "`n")

    $answer = Show-Choice 'Put a save back' $msg @('Cancel', 'Put it back')
    if ($answer -ne 'Put it back') { Log 'saves tab: restore cancelled'; return }

    $res = $null
    try { $res = Restore-SaveSnapshot -SavesRoot (Join-Path $Root 'saves') -VersionRoot $script:saveVersionRoot -Snapshot $snap }
    catch {
        Log ("saves tab: restore threw - {0}" -f $_.Exception.Message)
        [void](Show-Choice 'Setup Wizard' ("The restore hit an error:`n`n{0}`n`nSee wizard.log." -f $_.Exception.Message) @('OK'))
        return
    }

    Log ("saves tab: restored {0}, skipped {1}, failed {2}" -f $res.Restored, $res.Skipped, $res.Failed)
    foreach ($m in @($res.Messages)) { Log ('   ' + $m) }

    if ($res.Failed -gt 0) {
        [void](Show-Choice 'Setup Wizard' ("{0} put back, {1} left alone, {2} FAILED.`n`nSee wizard.log for which ones." -f $res.Restored, $res.Skipped, $res.Failed) @('OK'))
    }
    else {
        [void](Show-Choice 'Setup Wizard' ("Done. {0} put back, {1} left alone." -f $res.Restored, $res.Skipped) @('OK'))
    }

    # The restored files now look changed to the backup, which is correct: the
    # next run records them. Re-read so the dates on screen are honest.
    $keepId = $g.GameId; $keepSys = $g.System
    Initialize-Saves
    $script:saveSelected = @($script:saveGames | Where-Object { $_.GameId -eq $keepId -and $_.System -eq $keepSys })[0]
    Render-SaveConsoleList
    Render-SaveGames
}

# --- go ---------------------------------------------------------------------
Log ("started ({0} mode)" -f $(if ($Setup) { 'Setup' } elseif ($Play) { 'Play' } else { 'window' }))

# ===========================================================================
#  WHAT EACH WAY IN IS ALLOWED TO WRITE  (changed 2026-09-18)
# ===========================================================================
#  This used to rebuild the drive's two icon shortcuts AND this computer's
#  Start Menu buttons on every single launch, including every press of PLAY.
#  It was well meant - a .lnk stores an absolute path, so the one written last
#  week points at the wrong place once the drive comes back as a different
#  letter, and rewriting it is the whole repair.
#
#  It was still wrong. PLAY is the everyday button, pressed by anybody, and
#  the everyday button should look at the drive and nothing else. Nobody wants
#  icons appearing on a computer because they pressed Play.
#
#  So now:
#      PLAY.bat              writes NOTHING. Checks, and launches.
#      the wizard window     puts the SETUP button back if it has gone
#                            missing, and nothing else
#      SETUP RETROBAT.bat    rebuilds all of it, because that is what it is
#      Help tab              the same, on purpose, one button
#
#  The repair did not disappear, it moved to the button whose job it is. A
#  broken icon is one press of SETUP RETROBAT away from working, and that
#  button is a real file sitting at the top of the drive where it can always
#  be found.
# ---------------------------------------------------------------------------
if ($script:shortcutsOk -and -not $Play) {
    # Only ever ADDS a missing file. Never overwrites, never deletes. See
    # Update-RootFiles in scripts\Shortcuts.ps1.
    [void](Update-RootFiles -Root $Root -Logger { param($m) Log $m })
}

if     ($Setup) { Start-SetupFlow }
elseif ($Play)  { Start-PlayFlow }
else            { Show-MainWindow $null 'play' }
# Belt and braces: whatever path was taken, the splash is gone by now.
Close-Splash
Log 'done'

}
catch {
    try { Close-Splash } catch { }
    Log ("FATAL: {0}" -f $_.Exception.Message)
    Log ($_.ScriptStackTrace)
    $crashMsg = $_.Exception.Message
    $crashStack = [string]$_.ScriptStackTrace
    try {
        if ($script:bugOk) {
            # The one place a report is offered without being asked for: the
            # wizard itself just fell over. Still a question, never automatic.
            $ans = [System.Windows.MessageBox]::Show(
                "The Setup Wizard hit an error:`n`n$crashMsg`n`nSend a bug report so it can be fixed? It holds the error and the wizard's recent logs, with your Windows name taken out.",
                'Setup Wizard', 'YesNo', 'Error')
            if ([string]$ans -eq 'Yes') {
                $body = New-BugReport $Ws 'The wizard crashed (sent from the crash message).' $true ($crashMsg + "`n" + $crashStack)
                $r = Send-BugReport $Ws (Get-BugTitle '' $crashMsg) $body
                Log ("crash report: {0}" -f $r.Message)
                [void][System.Windows.MessageBox]::Show($r.Message, 'Setup Wizard', 'OK', 'Information')
            }
            $again = [System.Windows.MessageBox]::Show('Open the wizard again?', 'Setup Wizard', 'YesNo', 'Question')
            if ([string]$again -eq 'Yes') {
                Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\wscript.exe') -ArgumentList @('//nologo', ('"' + (Join-Path $WizardDir 'Launch-Wizard.vbs') + '"'))
            }
        }
        else {
            [void][System.Windows.MessageBox]::Show(
                "The Setup Wizard hit an error:`n`n$crashMsg`n`nDetails: _ClaudeWorkspace\wizard\wizard.log",
                'Setup Wizard', 'OK', 'Error')
        }
    } catch { }
    exit 1
}
