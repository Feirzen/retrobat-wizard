<#
    SteamUI.ps1
    ---------------------------------------------------------------------------
    The two windows for the Steam system: Connect Steam, and Disconnect Steam
    from this hard drive.

    FUNCTIONS ONLY. Dot-source it. It draws nothing until something calls
    Show-ConnectSteamWindow or Show-DisconnectSteamWindow.

    SELF CONTAINED ON PURPOSE. It builds its own colours and its own little
    text and button helpers rather than borrowing the wizard's, so it can be
    run from a .bat on its own when the wizard is broken or not open. That is
    the same rule every other engine on this drive follows.

    WHY IT IS ONE WINDOW AND NOT FOUR DIALOGS. Connecting Steam on a strange
    computer is four jobs with waiting in between: install, sign in, let Steam
    see the drive, build the tiles. A chain of pop-ups loses its place the
    moment somebody clicks the Steam window instead. One window that stays put
    and redraws its middle can say where you are and what is left.

    WHAT IT AUTOMATES AND WHAT IT DOES NOT. Everything except typing a
    password. Signing in is the user's job, always, and the window waits on a
    plain question - "Are you signed in?" - rather than trying to read the
    screen. Every other step does as much as it can and then asks whether it
    worked.

    RULES HONOURED HERE (see the customization record):
      - no drive letters anywhere; everything derives from -Root
      - no $PSScriptRoot inside a param() block
      - Windows PowerShell 5.1 only, no PowerShell 7 syntax
      - pure ASCII, no byte-order mark
      - event handlers touch script scope only. A handler in Windows
        PowerShell cannot be relied on to see a function's locals, which is
        the trap this project has fallen into more than once.
#>

Set-StrictMode -Off

Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
Add-Type -AssemblyName PresentationCore -ErrorAction SilentlyContinue
Add-Type -AssemblyName WindowsBase -ErrorAction SilentlyContinue

# The artwork engine, for the game picker's "what kind of game is this" and
# the offer to fetch pictures at the end. Loaded here at the top so its
# functions land in the same scope as these (a load inside a function would
# be invisible to the window's buttons). Everything still works without it:
# the picker just cannot say which games are couch multiplayer.
$suArtLib = Join-Path $PSScriptRoot 'SteamArtwork.ps1'
if (Test-Path -LiteralPath $suArtLib) { try { . $suArtLib } catch { } }

# --- the same dark palette the wizard uses ---------------------------------
$script:SuBg    = '#FF1E1E24'
$script:SuPanel = '#FF2A2A34'
$script:SuText  = '#FFE8E8EC'
$script:SuDim   = '#FF9A9AA6'
$script:SuGold  = '#FFE5B83B'
$script:SuGreen = '#FF7FD17F'
$script:SuWarn  = '#FFE0A050'

# Light / dark / follow Windows, shared by every window (scripts\Theme.ps1,
# 2026-10-13). Missing file = the original dark colours, untouched.
try { . (Join-Path $PSScriptRoot 'Theme.ps1') } catch { }
if (-not (Get-Command Convert-ThemeHex -ErrorAction SilentlyContinue)) { function Convert-ThemeHex([string]$hex) { return $hex } }

function New-SuBrush([string]$hex) {
    return (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString((Convert-ThemeHex $hex))))
}

function New-SuText([string]$text, [string]$colour, [int]$size = 14, [bool]$bold = $false) {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $text
    $tb.Foreground = (New-SuBrush $colour)
    $tb.FontSize = $size
    $tb.TextWrapping = 'Wrap'
    if ($bold) { $tb.FontWeight = 'Bold' }
    return $tb
}

function New-SuButton([string]$label, [string]$tag) {
    $b = New-Object System.Windows.Controls.Button
    $b.Content = $label
    $b.Padding = '16,7'
    $b.FontSize = 14
    $b.Margin = '8,0,0,0'
    $b.Tag = $tag
    return $b
}

# Force the window to repaint before a slow job blocks it. Without this the
# window looks frozen for the twenty seconds Steam takes to shut down, and a
# frozen window reads as a broken one.
function Update-SuWindow {
    try {
        if ($null -ne $script:suWin) {
            $script:suWin.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [action]{}) | Out-Null
        }
    }
    catch { }
}

# ===========================================================================
#  CONNECT STEAM
# ===========================================================================

function Show-ConnectSteamWindow {
    param([string]$Root, [string]$Title = 'Connect Steam')

    # --- state, all in script scope so the handlers can reach it -----------
    $script:suRoot      = $Root
    $script:suStep      = 1
    $script:suDone      = $false
    $script:suBusy      = $false
    $script:suLibrary   = Get-SteamDriveLibrary -Root $Root
    $script:suSteamRoot = Get-SteamRootOnComputer -Root $Root
    $script:suAccount   = ''
    $script:suPersona   = ''
    $script:suMode      = 'owner'
    $script:suFilter    = 'couch'
    $script:suCands     = @()
    $script:suChecks    = @{}
    $script:suArtTodo   = @()
    $script:suResult    = ''

    # --- the frame ---------------------------------------------------------
    $w = New-Object System.Windows.Window
    $w.Title = $Title
    $w.Width = 660
    $w.Height = 600
    $w.WindowStartupLocation = 'CenterScreen'
    $w.ResizeMode = 'CanResize'
    $w.Background = (New-SuBrush $script:SuBg)
    $script:suWin = $w

    $outer = New-Object System.Windows.Controls.DockPanel
    $outer.Margin = '0'

    # header
    $header = New-Object System.Windows.Controls.Border
    $header.Background = (New-SuBrush $script:SuPanel)
    $header.Padding = '22,14,22,14'
    [System.Windows.Controls.DockPanel]::SetDock($header, 'Top')
    $hsp = New-Object System.Windows.Controls.StackPanel
    $htitle = New-SuText 'Steam setup' $script:SuGold 19 $true
    [void]$hsp.Children.Add($htitle)
    $script:suStepLabel = New-SuText '' $script:SuDim 13
    $script:suStepLabel.Margin = '0,4,0,0'
    [void]$hsp.Children.Add($script:suStepLabel)
    $header.Child = $hsp
    [void]$outer.Children.Add($header)

    # button row at the bottom
    $footer = New-Object System.Windows.Controls.Border
    $footer.Background = (New-SuBrush $script:SuPanel)
    $footer.Padding = '22,12,22,12'
    [System.Windows.Controls.DockPanel]::SetDock($footer, 'Bottom')
    $frow = New-Object System.Windows.Controls.StackPanel
    $frow.Orientation = 'Horizontal'
    $frow.HorizontalAlignment = 'Right'

    $script:suCancelBtn = New-SuButton 'Cancel' 'cancel'
    $script:suCancelBtn.Add_Click({ $script:suResult = 'cancel'; $script:suWin.Close() })
    [void]$frow.Children.Add($script:suCancelBtn)

    $script:suSecondBtn = New-SuButton 'Second' 'second'
    $script:suSecondBtn.Visibility = 'Collapsed'
    $script:suSecondBtn.Add_Click({ Invoke-SuSecond })
    [void]$frow.Children.Add($script:suSecondBtn)

    $script:suMainBtn = New-SuButton 'Next' 'main'
    $script:suMainBtn.Add_Click({ Invoke-SuMain })
    [void]$frow.Children.Add($script:suMainBtn)

    $footer.Child = $frow
    [void]$outer.Children.Add($footer)

    # the middle, rebuilt per step
    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = 'Auto'
    $scroll.Padding = '22,18,22,18'
    $script:suBody = New-Object System.Windows.Controls.StackPanel
    $scroll.Content = $script:suBody
    [void]$outer.Children.Add($scroll)

    $w.Content = $outer

    Render-SuStep
    [void]$w.ShowDialog()

    return $script:suResult
}

# --- drawing one step ------------------------------------------------------

function Add-SuLine([string]$text, [string]$colour = '', [int]$size = 14, [bool]$bold = $false, [string]$margin = '0,0,0,10') {
    if ($colour -eq '') { $colour = $script:SuText }
    $t = New-SuText $text $colour $size $bold
    $t.Margin = $margin
    [void]$script:suBody.Children.Add($t)
    return $t
}

function Render-SuStep {
    $script:suBody.Children.Clear()
    $script:suSecondBtn.Visibility = 'Collapsed'
    $script:suSecondBtn.IsEnabled = $true
    $script:suMainBtn.IsEnabled = $true
    $script:suCancelBtn.IsEnabled = $true

    switch ($script:suStep) {
        1 { Render-SuStepInstall }
        2 { Render-SuStepSignIn }
        3 { Render-SuStepLibrary }
        4 { Render-SuStepChoose }
        5 { Render-SuStepPick }
        6 { Render-SuStepArtwork }
        7 { Render-SuStepDone }
    }
}

# --- step 1: is Steam on this computer at all ------------------------------

function Render-SuStepInstall {
    $script:suStepLabel.Text = 'Steam on this computer'
    $script:suSteamRoot = Get-SteamRootOnComputer -Root $script:suRoot

    [void](Add-SuLine 'Is Steam installed here?' $script:SuText 17 $true '0,0,0,14')

    if ($script:suSteamRoot -ne '') {
        [void](Add-SuLine 'Yes. Steam is already installed on this computer.' $script:SuGreen 15 $true)
        [void](Add-SuLine ('It lives in ' + $script:suSteamRoot) $script:SuDim 13)
        [void](Add-SuLine 'Nothing to do here. Press Next.' $script:SuText 14 $false '0,12,0,0')
        $script:suMainBtn.Content = 'Next'
        return
    }

    [void](Add-SuLine 'No. Steam is not installed on this computer yet.' $script:SuWarn 15 $true)
    [void](Add-SuLine 'The games are on this drive, but they still need the Steam program to start them. That is how the games themselves are built and there is no way round it.' $script:SuText 14)

    $installer = Join-Path $script:suRoot '_Wizard\Apps\tools\SteamSetup.exe'
    if (Test-Path -LiteralPath $installer) {
        [void](Add-SuLine 'The installer is on this drive, so nothing needs downloading to start it.' $script:SuDim 13)
        $script:suMainBtn.Content = 'Install Steam'
    }
    else {
        [void](Add-SuLine 'The installer is not on this drive, so this opens Steam''s own download page instead.' $script:SuDim 13)
        $script:suMainBtn.Content = 'Open the download page'
    }

    [void](Add-SuLine 'Two things to expect. Windows will ask permission, so this needs to be somebody''s own computer or an administrator standing next to you. And the first time Steam opens it downloads a few hundred megabytes of its own updates, which takes a few minutes.' $script:SuDim 13 $false '0,12,0,0')
}

# --- step 2: who is signed in, and whose games ------------------------------
#
#  The wizard cannot sign anybody in - only Steam can, and a password never
#  passes through this drive. What it CAN do is see who Steam is signed in as,
#  and ask whose games these are:
#
#    the drive owner   - the games on this drive (it belongs to them) plus
#                        anything downloaded on this computer
#    somebody else     - only the games downloaded on this computer, under
#                        their own account. Their Steam settings are never
#                        touched: this drive is not added to their Steam.

function Render-SuStepSignIn {
    $script:suStepLabel.Text = 'Signing in'
    $u = Get-SteamLoginUser -Root $script:suRoot
    $script:suAccount = [string]$u.Account
    $script:suPersona = [string]$u.Persona

    [void](Add-SuLine 'Who is Steam signed in as?' $script:SuText 17 $true '0,0,0,14')

    if ($script:suAccount -eq '') {
        [void](Add-SuLine 'Nobody is signed in yet.' $script:SuWarn 15 $true)
        [void](Add-SuLine 'Steam has to be signed in before any Steam game will start, as whoever owns the games you want to play.' $script:SuText 14)
        [void](Add-SuLine 'This opens Steam''s sign-in window. Type your details there - nothing on this drive ever sees or stores a password. Steam may also want a code from a phone the first time on a new computer.' $script:SuDim 13)
        $script:suMainBtn.Content = 'Open Steam''s sign-in'
        return
    }

    $who = $script:suAccount
    if ($script:suPersona -ne '') { $who = $script:suPersona + '  (' + $script:suAccount + ')' }
    [void](Add-SuLine $who $script:SuGreen 16 $true)

    $owner = Get-SteamDriveOwner -Root $script:suRoot
    $ownerName = 'the drive owner'
    if ($owner.Persona -ne '') { $ownerName = $owner.Persona }
    elseif ($owner.Account -ne '') { $ownerName = $owner.Account }

    # Pre-select from what is known: the remembered owner, or what this
    # computer was set to last time.
    $isOwner = $true
    if ($owner.Account -ne '') { $isOwner = ($owner.Account -ieq $script:suAccount) }
    $prev = Get-SteamProfileState -Root $script:suRoot
    if ($prev.Connected -and $prev.Mode -eq 'guest' -and ([string]$prev.Account -ieq $script:suAccount)) { $isOwner = $false }

    # 2026-10-13 (Steven): most people will NOT carry Steam games on a drive -
    # they just want the Steam library they already have to show up. So the
    # drive option is only offered when the drive actually has a Steam games
    # folder; otherwise this page simply says what will happen.
    $hasDriveLib = ((Get-SteamDriveLibrary -Root $script:suRoot) -ne '')

    $script:suOwnerRb = New-Object System.Windows.Controls.RadioButton
    $script:suOwnerRb.Content = 'My games on this computer, plus the ones on this drive'
    $script:suOwnerRb.Foreground = (New-SuBrush $script:SuText)
    $script:suOwnerRb.FontSize = 15
    $script:suOwnerRb.IsChecked = ($isOwner -and $hasDriveLib)
    $o1txt = 'Also lets Steam see the games folder on this drive. That only adds to Steam''s list - nothing already installed moves.'
    if ($owner.Account -ne '') { $o1txt += (' The drive''s games belong to ' + $ownerName + '''s account.') }
    $o1 = New-SuText $o1txt $script:SuDim 13
    $o1.Margin = '26,2,0,10'

    $script:suGuestRb = New-Object System.Windows.Controls.RadioButton
    $script:suGuestRb.Content = 'Just the games already on this computer'
    $script:suGuestRb.Foreground = (New-SuBrush $script:SuText)
    $script:suGuestRb.FontSize = 15
    $script:suGuestRb.IsChecked = (-not ($isOwner -and $hasDriveLib))
    $g1 = New-SuText 'Uses the Steam games already downloaded here, on any drive Steam uses. Your Steam settings are left exactly as they are.' $script:SuDim 13
    $g1.Margin = '26,2,0,10'

    if ($hasDriveLib) {
        [void](Add-SuLine 'Which Steam games should RetroBat show?' $script:SuText 14 $false '0,6,0,8')
        [void]$script:suBody.Children.Add($script:suGuestRb)
        [void]$script:suBody.Children.Add($g1)
        [void]$script:suBody.Children.Add($script:suOwnerRb)
        [void]$script:suBody.Children.Add($o1)
    }
    else {
        [void](Add-SuLine 'RetroBat will show the Steam games already downloaded on this computer, wherever Steam keeps them.' $script:SuText 14 $false '0,6,0,6')
        [void](Add-SuLine 'Your Steam settings are left exactly as they are. You pick which games show on the next page.' $script:SuDim 13 $false '0,0,0,10')
    }

    [void](Add-SuLine 'Wrong person signed in? "Sign in as someone else" switches Steam over first.' $script:SuDim 13 $false '0,4,0,0')
    if (Test-SteamRunning) {
        [void](Add-SuLine 'Steam is open right now. Switching accounts closes it first, which stops any game running in it.' $script:SuWarn 13 $false '0,6,0,0')
    }

    $script:suMainBtn.Content = 'Next'
    $script:suSecondBtn.Content = 'Sign in as someone else'
    $script:suSecondBtn.Visibility = 'Visible'
}

# --- step 3: let Steam see the drive ---------------------------------------

function Render-SuStepLibrary {
    $script:suStepLabel.Text = 'Letting Steam see this drive'
    $script:suSteamRoot = Get-SteamRootOnComputer -Root $script:suRoot
    $script:suLibrary   = Get-SteamDriveLibrary -Root $script:suRoot

    [void](Add-SuLine 'Where Steam looks for games' $script:SuText 17 $true '0,0,0,14')

    if ($script:suLibrary -eq '') {
        [void](Add-SuLine 'No Steam games folder was found on this drive.' $script:SuWarn 15 $true)
        [void](Add-SuLine 'That is fine. Games downloaded on this computer can still be chosen on the next page.' $script:SuText 14)
        [void](Add-SuLine 'To carry games on the drive itself: on your own computer open Steam, Settings, Storage, add this drive, then use Move on the games you want to take with you.' $script:SuDim 13)
        $script:suMainBtn.Content = 'Next'
        return
    }

    if (Test-SteamLibraryRegistered -SteamRoot $script:suSteamRoot -LibraryPath $script:suLibrary) {
        [void](Add-SuLine 'Steam already knows about this drive.' $script:SuGreen 15 $true)
        [void](Add-SuLine 'Nothing needs changing. Press Next to choose which games show.' $script:SuText 14)
        $script:suMainBtn.Content = 'Next'
        return
    }

    [void](Add-SuLine 'Steam keeps a list of the folders it looks in for games. This drive is not on that list yet, so Steam cannot see the games sitting on it.' $script:SuText 14)
    [void](Add-SuLine ('The folder to add is:  ' + $script:suLibrary) $script:SuGold 14 $true)
    [void](Add-SuLine 'This ADDS to the list. It does not replace anything. Every game already installed on this computer stays exactly where it is and keeps working, including after this drive is unplugged again.' $script:SuText 14)

    # the two ways
    $script:suAuto = New-Object System.Windows.Controls.RadioButton
    $script:suAuto.Content = 'Automatic'
    $script:suAuto.Foreground = (New-SuBrush $script:SuText)
    $script:suAuto.FontSize = 15
    $script:suAuto.IsChecked = $false
    $script:suAuto.Margin = '0,8,0,0'
    [void]$script:suBody.Children.Add($script:suAuto)

    $a1 = New-SuText 'Closes Steam, writes this drive into Steam''s list itself, opens Steam again. Faster, but Steam does not always accept it. A dated copy of the old list is saved onto this drive first, so the Disconnect button can put everything back in one click.' $script:SuDim 13
    $a1.Margin = '26,4,0,12'
    [void]$script:suBody.Children.Add($a1)

    $script:suManual = New-Object System.Windows.Controls.RadioButton
    $script:suManual.Content = 'Let Steam add it   (recommended)'
    $script:suManual.Foreground = (New-SuBrush $script:SuText)
    $script:suManual.FontSize = 15
    [void]$script:suBody.Children.Add($script:suManual)

    $script:suManual.IsChecked = $true
    $m1 = New-SuText 'Opens Steam''s own storage settings and tells you what to click (Add Drive, then pick this drive). Steam does the writing itself, which is the one way it always accepts.' $script:SuDim 13
    $m1.Margin = '26,4,0,0'
    [void]$script:suBody.Children.Add($m1)

    $script:suMainBtn.Content = 'Do it'
}

# --- step 4: which kinds of game -------------------------------------------

function Render-SuStepChoose {
    $script:suStepLabel.Text = 'Choosing games'
    $script:suCands = @(Get-SteamCandidateGames -Root $script:suRoot -Mode $script:suMode)

    [void](Add-SuLine 'Which games should show in RetroBat on this computer?' $script:SuText 17 $true '0,0,0,12')

    $where = 'on this computer'
    if ($script:suMode -eq 'owner') { $where = 'on this drive and on this computer' }

    if ($script:suCands.Count -eq 0) {
        [void](Add-SuLine ('No downloaded Steam games were found ' + $where + '.') $script:SuWarn 15 $true)
        [void](Add-SuLine 'Download a game in Steam, then run this again. Only downloaded games are offered, so every tile starts straight away instead of starting a download in the middle of a party.' $script:SuText 14)
        $script:suMainBtn.Content = 'Close'
        $script:suStep = 99
        return
    }

    [void](Add-SuLine ('{0} downloaded game(s) found {1}. Tick the kinds you want; the next page lists them so you can untick any one.' -f $script:suCands.Count, $where) $script:SuText 14)

    # Start from what this computer had last time, else couch only.
    $prev = Get-SteamProfileState -Root $script:suRoot
    $f = 'couch'
    if ($prev.Connected -and $prev.Mode -ne '') { $f = $prev.Filter }

    $script:suCouchCb = New-Object System.Windows.Controls.CheckBox
    $script:suCouchCb.Content = 'Couch multiplayer'
    $script:suCouchCb.Foreground = (New-SuBrush $script:SuText)
    $script:suCouchCb.FontSize = 15
    $script:suCouchCb.Margin = '0,8,0,0'
    $script:suCouchCb.IsChecked = ($f -eq 'couch' -or $f -eq 'all')
    [void]$script:suBody.Children.Add($script:suCouchCb)
    $c1 = New-SuText 'Games you can play together on one screen: co-op, versus and party games.' $script:SuDim 13
    $c1.Margin = '26,2,0,10'
    [void]$script:suBody.Children.Add($c1)

    $script:suSoloCb = New-Object System.Windows.Controls.CheckBox
    $script:suSoloCb.Content = 'Solo and online-only games'
    $script:suSoloCb.Foreground = (New-SuBrush $script:SuText)
    $script:suSoloCb.FontSize = 15
    $script:suSoloCb.IsChecked = ($f -eq 'solo' -or $f -eq 'all')
    [void]$script:suBody.Children.Add($script:suSoloCb)
    $s1 = New-SuText 'Everything else that is downloaded.' $script:SuDim 13
    $s1.Margin = '26,2,0,10'
    [void]$script:suBody.Children.Add($s1)

    [void](Add-SuLine 'Which games are couch multiplayer is Steam''s own answer, asked once per game over the internet and remembered on the drive after that.' $script:SuDim 13 $false '0,8,0,0')

    $script:suMainBtn.Content = 'Next'
}

# --- step 5: the checklist ---------------------------------------------------

function Render-SuStepPick {
    $script:suStepLabel.Text = 'Choosing games'
    $info = Get-SteamGameInfo -Root $script:suRoot
    $prev = Get-SteamProfileState -Root $script:suRoot
    $usePrev = ($prev.Connected -and $prev.Mode -eq $script:suMode -and $prev.Filter -eq $script:suFilter)

    [void](Add-SuLine 'Untick anything you do not want' $script:SuText 17 $true '0,0,0,8')

    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    $row.Margin = '0,0,0,10'
    $all = New-Object System.Windows.Controls.Button
    $all.Content = 'Tick all'; $all.Padding = '10,3'; $all.FontSize = 13
    $all.Add_Click({ foreach ($cb in $script:suChecks.Values) { $cb.IsChecked = $true } })
    [void]$row.Children.Add($all)
    $none = New-Object System.Windows.Controls.Button
    $none.Content = 'Untick all'; $none.Padding = '10,3'; $none.FontSize = 13; $none.Margin = '8,0,0,0'
    $none.Add_Click({ foreach ($cb in $script:suChecks.Values) { $cb.IsChecked = $false } })
    [void]$row.Children.Add($none)
    [void]$script:suBody.Children.Add($row)

    $script:suChecks = @{}
    foreach ($g in $script:suCands) {
        $i = $info[[string]$g.AppId]

        $ticked = Test-SteamGameFitsFilter -Info $i -Filter $script:suFilter
        if ($usePrev) {
            if (@($prev.Picked) -contains [string]$g.AppId)   { $ticked = $true }
            if (@($prev.Unpicked) -contains [string]$g.AppId) { $ticked = $false }
        }

        $sp = New-Object System.Windows.Controls.StackPanel
        $n = New-SuText ([string]$g.Name) $script:SuText 14
        [void]$sp.Children.Add($n)
        $k = New-SuText (Get-SteamGameKindText -Info $i) $script:SuDim 12
        [void]$sp.Children.Add($k)

        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $sp
        $cb.IsChecked = $ticked
        $cb.Margin = '0,0,0,8'
        $cb.VerticalContentAlignment = 'Top'
        [void]$script:suBody.Children.Add($cb)
        $script:suChecks[[string]$g.AppId] = $cb
    }

    [void](Add-SuLine 'Remembered for this computer. Run Steam setup again any time to change it. A game downloaded later shows up by itself if it fits the kinds ticked on the last page.' $script:SuDim 13 $false '0,8,0,0')
    $script:suMainBtn.Content = 'Save'
}

# --- step 6: pictures ----------------------------------------------------------

function Render-SuStepArtwork {
    $script:suStepLabel.Text = 'Pictures and trailers'
    $script:suArtTodo = @()
    if (Get-Command -Name 'Test-SaArtworkMissing' -ErrorAction SilentlyContinue) {
        foreach ($g in @(Get-SteamWantedGames -Root $script:suRoot)) {
            $tile = ConvertTo-SafeShortcutName -Name $g.Name
            if (Test-SaArtworkMissing -Root $script:suRoot -TileName $tile) { $script:suArtTodo += $g }
        }
    }
    if ($script:suArtTodo.Count -eq 0) {
        $script:suStep = 7
        Render-SuStep
        return
    }

    [void](Add-SuLine ('{0} of these games have no pictures or trailer yet' -f $script:suArtTodo.Count) $script:SuText 17 $true '0,0,0,12')
    foreach ($g in $script:suArtTodo) {
        $t = New-SuText ('   ' + $g.Name) $script:SuDim 13
        $t.Margin = '0,0,0,2'
        [void]$script:suBody.Children.Add($t)
    }
    [void](Add-SuLine 'Fetch them from Steam now? It needs the internet and takes about ten seconds a game. They are kept on the drive afterwards, so this only ever happens once per game - even if the drive comes back to this computer months from now.' $script:SuText 14 $false '0,12,0,0')
    [void](Add-SuLine 'Skipping is fine too: Get Steam Artwork in Maintenance Steps does the same job later.' $script:SuDim 13)

    $script:suMainBtn.Content = 'Fetch now'
    $script:suSecondBtn.Content = 'Skip'
    $script:suSecondBtn.Visibility = 'Visible'
}

# --- step 7: done ------------------------------------------------------------

function Render-SuStepDone {
    $script:suStepLabel.Text = 'Done'

    [void](Add-SuLine 'Steam is set up on this computer' $script:SuGreen 17 $true '0,0,0,14')

    $shown = @(Get-SteamWantedGames -Root $script:suRoot)
    [void](Add-SuLine ('{0} game(s) will show in RetroBat.' -f $shown.Count) $script:SuText 15 $true)

    foreach ($g in $shown) {
        $t = New-SuText ('   ' + $g.Name) $script:SuDim 13
        $t.Margin = '0,0,0,2'
        [void]$script:suBody.Children.Add($t)
    }

    if ($script:suMode -eq 'owner') {
        $busy = @(Get-SteamGamesOnDrive -Root $script:suRoot | Where-Object { -not $_.Installed })
        if ($busy.Count -gt 0) {
            [void](Add-SuLine ('{0} more on the drive are still downloading. They can be chosen once they finish - run Steam setup again then.' -f $busy.Count) $script:SuWarn 13 $false '0,14,0,0')
        }
    }

    [void](Add-SuLine 'This is remembered for THIS computer only. Plug the drive into a different one and Steam games stay hidden there until Steam setup is run on it too. To change the games, run Steam setup again; to take it all back off, use Disconnect Steam on the wizard''s Machine tab.' $script:SuDim 13 $false '0,14,0,0')

    $script:suMainBtn.Content = 'Finish'
    $script:suCancelBtn.Visibility = 'Collapsed'
}

# --- what the buttons do ---------------------------------------------------

function Set-SuBusy([string]$message) {
    $script:suBusy = $true
    $script:suMainBtn.IsEnabled = $false
    $script:suCancelBtn.IsEnabled = $false
    $script:suSecondBtn.IsEnabled = $false
    $script:suStepLabel.Text = $message
    Update-SuWindow
}

function Clear-SuBusy {
    $script:suBusy = $false
    $script:suMainBtn.IsEnabled = $true
    $script:suCancelBtn.IsEnabled = $true
    $script:suSecondBtn.IsEnabled = $true
}

function Invoke-SuMain {
    if ($script:suBusy) { return }

    switch ($script:suStep) {

        1 {
            if ((Get-SteamRootOnComputer -Root $script:suRoot) -ne '') {
                $script:suStep = 2
                Render-SuStep
                return
            }

            # Not installed. Either we already offered, or we are offering now.
            if ([string]$script:suMainBtn.Content -eq 'Check again') {
                Render-SuStep
                if ((Get-SteamRootOnComputer -Root $script:suRoot) -eq '') {
                    $script:suMainBtn.Content = 'Check again'
                    [void](Add-SuLine 'Still not finding it. Finish the Steam installer, then press Check again.' $script:SuWarn 13 $false '0,12,0,0')
                }
                return
            }

            $installer = Join-Path $script:suRoot '_Wizard\Apps\tools\SteamSetup.exe'
            try {
                if (Test-Path -LiteralPath $installer) {
                    Start-Process -FilePath $installer -ErrorAction SilentlyContinue | Out-Null
                }
                else {
                    Start-Process 'https://store.steampowered.com/about/' -ErrorAction SilentlyContinue | Out-Null
                }
            }
            catch { }

            $script:suBody.Children.Clear()
            [void](Add-SuLine 'Waiting for Steam to be installed' $script:SuText 17 $true '0,0,0,14')
            [void](Add-SuLine 'Follow the Steam installer, then come back here and press the button below. This window waits as long as it needs to.' $script:SuText 14)
            [void](Add-SuLine 'Leave Steam open when it finishes. The next step signs you in.' $script:SuDim 13)
            $script:suMainBtn.Content = 'Check again'
        }

        2 {
            $label = [string]$script:suMainBtn.Content

            if ($label -eq 'Open Steam''s sign-in') {
                Invoke-SuOpenSignIn
                return
            }

            # Coming back from the sign-in wait. Ask Windows who is signed in
            # now rather than taking the button press as proof, then show the
            # "whose games" choice for that person.
            if ($label -eq 'I am signed in') {
                $u = Get-SteamLoginUser -Root $script:suRoot
                if ([string]$u.Account -ne '') {
                    Render-SuStep
                }
                else {
                    [void](Add-SuLine 'Steam still does not show anybody signed in. Finish signing in over in Steam, give it a few seconds, then press the button again.' $script:SuWarn 13 $false '0,12,0,0')
                }
                return
            }

            # 'Next': whose games.
            $script:suMode = 'owner'
            try { if ($script:suGuestRb -and $script:suGuestRb.IsChecked) { $script:suMode = 'guest' } } catch { }

            if ($script:suMode -eq 'owner') {
                $owner = Get-SteamDriveOwner -Root $script:suRoot
                if ($owner.Account -eq '') { [void](Set-SteamDriveOwner -Root $script:suRoot -Account $script:suAccount -Persona $script:suPersona) }
                $script:suStep = 3
            }
            else {
                # A friend's computer: the drive is NOT added to their Steam.
                $script:suStep = 4
            }
            Render-SuStep
        }

        3 {
            $auto = $true
            try { if ($script:suManual -and $script:suManual.IsChecked) { $auto = $false } } catch { }

            # Already registered, no library on the drive, or waiting on a
            # manual add.
            if ([string]$script:suMainBtn.Content -eq 'Next') {
                Invoke-SuFinishConnect
                return
            }

            if ([string]$script:suMainBtn.Content -eq 'I have added it') {
                if (Test-SteamLibraryRegistered -SteamRoot $script:suSteamRoot -LibraryPath $script:suLibrary) {
                    Invoke-SuFinishConnect
                }
                else {
                    [void](Add-SuLine 'Steam still does not list this drive. Check you picked the right folder, then press the button again.' $script:SuWarn 13 $false '0,12,0,0')
                }
                return
            }

            if ($auto) { Invoke-SuAutoLibrary }
            else       { Invoke-SuManualLibrary }
        }

        4 { Invoke-SuChoose }
        5 { Invoke-SuSave }
        6 { Invoke-SuFetchArtwork }

        7 {
            $script:suResult = 'connected'
            $script:suWin.Close()
        }

        99 {
            $script:suResult = 'nothing to do'
            $script:suWin.Close()
        }
    }
}

function Invoke-SuSecond {
    if ($script:suBusy) { return }
    if ($script:suStep -eq 2) { Invoke-SuOpenSignIn; return }
    if ($script:suStep -eq 6) { $script:suStep = 7; Render-SuStep; return }
}

# Gets Steam to the sign-in screen and then waits on a plain question.
#
# Clearing AutoLoginUser is what makes Steam ASK rather than signing straight
# back in as whoever was there before. Without it, "sign in as someone else"
# on a computer that remembers its owner just reopens as the owner, which
# looks like the button did nothing.
function Invoke-SuOpenSignIn {
    Set-SuBusy 'Closing Steam so it can ask who is signing in...'
    [void](Stop-SteamClient -Root $script:suRoot -TimeoutSeconds 25)
    Update-SuWindow
    try {
        Set-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name 'AutoLoginUser' -Value '' -ErrorAction SilentlyContinue
    }
    catch { }
    [void](Start-SteamClient -Root $script:suRoot)
    Clear-SuBusy

    $script:suStep = 2
    $script:suStepLabel.Text = 'Signing in'
    $script:suBody.Children.Clear()
    [void](Add-SuLine 'Waiting for you to sign in' $script:SuText 17 $true '0,0,0,14')
    [void](Add-SuLine 'Steam has been reopened and should be asking for a login. Sign in as yourself over there, then come back and press the button below.' $script:SuText 14)
    [void](Add-SuLine 'Nothing on this drive sees or stores your password. Steam may also want a code from your phone the first time on this computer.' $script:SuDim 13)
    $script:suMainBtn.Content = 'I am signed in'
    $script:suSecondBtn.Visibility = 'Collapsed'
}

function Invoke-SuAutoLibrary {
    Set-SuBusy 'Closing Steam...'
    $wasRunning = Test-SteamRunning
    if ($wasRunning) {
        if (-not (Stop-SteamClient -Root $script:suRoot -TimeoutSeconds 30)) {
            Clear-SuBusy
            $script:suStepLabel.Text = 'Letting Steam see this drive'
            [void](Add-SuLine 'Steam would not close, so nothing was changed. Close Steam by hand from its own menu, then press Do it again.' $script:SuWarn 13 $false '0,12,0,0')
            return
        }
    }

    $script:suStepLabel.Text = 'Adding this drive to Steam''s list...'
    Update-SuWindow

    $r = Add-SteamLibraryFolder -Root $script:suRoot -SteamRoot $script:suSteamRoot -LibraryPath $script:suLibrary

    if (-not $r.Ok) {
        Clear-SuBusy
        $script:suStepLabel.Text = 'Letting Steam see this drive'
        [void](Add-SuLine ('It did not work: ' + $r.Message) $script:SuWarn 14 $true '0,12,0,4')
        [void](Add-SuLine 'Nothing was changed. Choose Manual instead and Steam will do the writing itself.' $script:SuText 13)
        return
    }

    $script:suStepLabel.Text = 'Opening Steam again...'
    Update-SuWindow
    [void](Start-SteamClient -Root $script:suRoot)

    Clear-SuBusy
    $script:suStep = 4
    Invoke-SuFinishConnect
}

function Invoke-SuManualLibrary {
    try {
        [System.Windows.Clipboard]::SetText($script:suLibrary)
    }
    catch { }

    try {
        if (Test-SteamRunning) {
            Start-Process 'steam://open/settings' -ErrorAction SilentlyContinue | Out-Null
        }
        else {
            [void](Start-SteamClient -Root $script:suRoot)
        }
    }
    catch { }

    $script:suBody.Children.Clear()
    [void](Add-SuLine 'Add the folder in Steam' $script:SuText 17 $true '0,0,0,14')
    [void](Add-SuLine '1.  In Steam, open Settings, then Storage.' $script:SuText 14 $false '0,0,0,6')
    [void](Add-SuLine '2.  Click the drive dropdown at the top, then "Add Drive".' $script:SuText 14 $false '0,0,0,6')
    [void](Add-SuLine '3.  Pick this drive. Steam finds the SteamLibrary folder itself.' $script:SuText 14 $false '0,0,0,6')
    [void](Add-SuLine '4.  Come back here and press the button below.' $script:SuText 14 $false '0,0,0,12')
    [void](Add-SuLine ('The folder, copied to your clipboard so you can paste it:  ' + $script:suLibrary) $script:SuGold 13)
    [void](Add-SuLine 'Steam adds it to its list alongside whatever is already there. Nothing you already have installed is moved or changed.' $script:SuDim 13 $false '0,10,0,0')

    $script:suMainBtn.Content = 'I have added it'
}

# The library step is over (or skipped): on to choosing games. Nothing is
# saved until the checklist's Save, so Cancel before then leaves this
# computer's RetroBat exactly as it was.
function Invoke-SuFinishConnect {
    $script:suStep = 4
    Render-SuStep
}

# Page 4's Next: work out the filter, then ask Steam once about any game the
# drive has not met before, so the checklist can say what each one is.
function Invoke-SuChoose {
    $couch = [bool]$script:suCouchCb.IsChecked
    $solo  = [bool]$script:suSoloCb.IsChecked
    if (-not $couch -and -not $solo) {
        [void](Add-SuLine 'Tick at least one of the two.' $script:SuWarn 13 $false '0,10,0,0')
        return
    }
    $script:suFilter = 'all'
    if ($couch -and -not $solo) { $script:suFilter = 'couch' }
    if ($solo -and -not $couch) { $script:suFilter = 'solo' }

    if (Get-Command -Name 'Update-SaGameInfoCache' -ErrorAction SilentlyContinue) {
        Set-SuBusy 'Asking Steam about your games...'
        $progress = {
            param($done, $total, $name)
            $script:suStepLabel.Text = ('Asking Steam about game {0} of {1}: {2}' -f $done, $total, $name)
            Update-SuWindow
        }
        try { [void](Update-SaGameInfoCache -Root $script:suRoot -Games $script:suCands -Progress $progress) } catch { }
        Clear-SuBusy
    }

    $script:suStep = 5
    Render-SuStep
}

# Page 5's Save: remember the choice for this computer, build the tiles.
function Invoke-SuSave {
    $picked = @()
    $unpicked = @()
    foreach ($k in @($script:suChecks.Keys)) {
        if ([bool]$script:suChecks[$k].IsChecked) { $picked += $k } else { $unpicked += $k }
    }

    Set-SuBusy 'Saving and building the game tiles...'
    $lib = ''
    if ($script:suMode -eq 'owner') { $lib = $script:suLibrary }
    [void](Set-SteamProfileState -Root $script:suRoot -Connected $true -Library $lib -Account $script:suAccount -Mode $script:suMode -Filter $script:suFilter -Picked $picked -Unpicked $unpicked)
    [void](Sync-SteamSystem -Root $script:suRoot)
    Clear-SuBusy

    $script:suStep = 6
    Render-SuStep
}

# Page 6's Fetch now: the same job as Get Steam Artwork, for just these games.
function Invoke-SuFetchArtwork {
    if ($null -ne (Get-Process -Name 'emulationstation' -ErrorAction SilentlyContinue)) {
        [void](Add-SuLine 'RetroBat is open. Close it first - it rewrites the game list when it closes, which would throw these pictures away. Then press Fetch now again.' $script:SuWarn 13 $false '0,12,0,0')
        return
    }

    Set-SuBusy 'Fetching pictures...'
    $results = @()
    $n = 0
    foreach ($g in $script:suArtTodo) {
        $n++
        $script:suStepLabel.Text = ('Fetching pictures {0} of {1}: {2}' -f $n, $script:suArtTodo.Count, $g.Name)
        Update-SuWindow
        try {
            $tile = ConvertTo-SafeShortcutName -Name $g.Name
            $results += (Get-SaGameArtwork -Root $script:suRoot -SteamRoot $script:suSteamRoot -AppId ([string]$g.AppId) -TileName $tile)
        }
        catch { }
    }
    if ($results.Count -gt 0) {
        $script:suStepLabel.Text = 'Writing the game list...'
        Update-SuWindow
        try { [void](Update-SaGameList -Root $script:suRoot -Results $results) } catch { }
    }
    Clear-SuBusy

    $script:suStep = 7
    Render-SuStep
}

# ===========================================================================
#  DISCONNECT STEAM FROM THIS HARD DRIVE
# ===========================================================================
#
#  Three independent things, ticked separately, because they are three
#  different sizes of undo:
#
#    - putting Steam's library list back      reverses step 3
#    - signing this account out               reverses step 2
#    - uninstalling Steam                     reverses step 1
#
#  Hiding the tiles happens whatever is ticked, because that is the whole
#  point of the button and it is the one part that touches nothing but this
#  drive.
# ---------------------------------------------------------------------------

function Show-DisconnectSteamWindow {
    param([string]$Root, [string]$Title = 'Disconnect Steam')

    $script:sudRoot = $Root
    $script:sudResult = ''

    $w = New-Object System.Windows.Window
    $w.Title = $Title
    $w.Width = 620
    $w.SizeToContent = 'Height'
    $w.WindowStartupLocation = 'CenterScreen'
    $w.ResizeMode = 'NoResize'
    $w.Background = (New-SuBrush $script:SuBg)
    $script:sudWin = $w
    $script:suWin  = $w

    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = '22'

    $t = New-SuText 'Disconnect Steam from this hard drive' $script:SuGold 18 $true
    $t.Margin = '0,0,0,10'
    [void]$sp.Children.Add($t)

    $t2 = New-SuText 'The Steam game tiles come off this computer either way. Tick anything else you want undone as well. Every one of these is safe to leave unticked.' $script:SuText 14
    $t2.Margin = '0,0,0,16'
    [void]$sp.Children.Add($t2)

    $script:sudLib = New-Object System.Windows.Controls.CheckBox
    $script:sudLib.Content = 'Put Steam''s list of game folders back'
    $script:sudLib.Foreground = (New-SuBrush $script:SuText)
    $script:sudLib.FontSize = 15
    [void]$sp.Children.Add($script:sudLib)
    $d1 = New-SuText 'Takes this drive back off the list, leaving every other folder exactly as it was. Worth doing on somebody else''s computer so nothing of yours is left behind.' $script:SuDim 13
    $d1.Margin = '26,4,0,14'
    [void]$sp.Children.Add($d1)

    $script:sudOut = New-Object System.Windows.Controls.CheckBox
    $script:sudOut.Content = 'Sign my Steam account out of this computer'
    $script:sudOut.Foreground = (New-SuBrush $script:SuText)
    $script:sudOut.FontSize = 15
    [void]$sp.Children.Add($script:sudOut)
    $d2 = New-SuText 'Steam asks for a login next time it opens. Do this before you walk away from a computer that is not yours.' $script:SuDim 13
    $d2.Margin = '26,4,0,14'
    [void]$sp.Children.Add($d2)

    $script:sudUnin = New-Object System.Windows.Controls.CheckBox
    $script:sudUnin.Content = 'Uninstall Steam from this computer'
    $script:sudUnin.Foreground = (New-SuBrush $script:SuText)
    $script:sudUnin.FontSize = 15
    [void]$sp.Children.Add($script:sudUnin)
    $d3 = New-SuText 'Hands over to Steam''s own uninstaller, which asks its own questions. Only tick this if Steam was installed for the sake of this drive and the owner wants it gone.' $script:SuDim 13
    $d3.Margin = '26,4,0,16'
    [void]$sp.Children.Add($d3)

    $script:sudNote = New-SuText '' $script:SuWarn 13
    $script:sudNote.Margin = '0,0,0,8'
    [void]$sp.Children.Add($script:sudNote)

    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    $row.HorizontalAlignment = 'Right'
    $row.Margin = '0,10,0,0'

    $cancel = New-SuButton 'Cancel' 'cancel'
    $cancel.Add_Click({ $script:sudResult = ''; $script:sudWin.Close() })
    [void]$row.Children.Add($cancel)

    $go = New-SuButton 'Disconnect' 'go'
    $go.Add_Click({ Invoke-SuDisconnect })
    $script:sudGo = $go
    [void]$row.Children.Add($go)

    [void]$sp.Children.Add($row)
    $w.Content = $sp
    [void]$w.ShowDialog()

    return $script:sudResult
}

function Invoke-SuDisconnect {
    $doLib  = [bool]$script:sudLib.IsChecked
    $doOut  = [bool]$script:sudOut.IsChecked
    $doUnin = [bool]$script:sudUnin.IsChecked

    # One are-you-sure, naming exactly what is about to happen. A separate
    # confirm per tick would be three clicks for one decision already made.
    $what = @('Hide the Steam game tiles on this computer.')
    if ($doLib)  { $what += 'Take this drive off Steam''s list of game folders.' }
    if ($doOut)  { $what += 'Sign your Steam account out of this computer.' }
    if ($doUnin) { $what += 'Start Steam''s own uninstaller.' }

    $msg = "About to:`n`n   -  " + ($what -join "`n   -  ")
    if ($doUnin) { $msg += "`n`nUninstalling Steam cannot be undone from here." }
    else { $msg += "`n`nAll of this can be done again by running Connect Steam." }

    # Inside the wizard, its own box, which a controller can answer
    # (2026-10-11). On its own (Connect Steam.bat), Windows' message box.
    if (Get-Command Show-Choice -ErrorAction SilentlyContinue) {
        if ((Show-Choice 'Are you sure?' $msg @('Go ahead', 'Cancel')) -ne 'Go ahead') { return }
    }
    else {
        $ans = [System.Windows.MessageBox]::Show($msg, 'Are you sure?', 'OKCancel', 'Warning')
        if ($ans -ne [System.Windows.MessageBoxResult]::OK) { return }
    }

    $script:sudGo.IsEnabled = $false
    $script:sudNote.Text = 'Working...'
    Update-SuWindow

    $r = Disconnect-Steam -Root $script:sudRoot -RestoreLibraries:$doLib -LogOut:$doOut -UninstallSteam:$doUnin

    $script:sudResult = 'disconnected'
    if (Get-Command Show-Choice -ErrorAction SilentlyContinue) { [void](Show-Choice 'Disconnect Steam' (($r.Steps) -join "`n") @('OK')) }
    else { [void][System.Windows.MessageBox]::Show((($r.Steps) -join "`n"), 'Disconnect Steam', 'OK', 'Information') }
    $script:sudWin.Close()
}
